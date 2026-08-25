"""Post-generation resume assistant — conversation first, edits when asked.

Once a resume exists the user wants two different things from the same chat box:
  - to ASK ("what skills am I missing for this job?", "is my summary strong?")
  - to CHANGE ("shorten the first bullet", "add Python to my skills")

So this module is not an edit pipeline with a chat skin; it is a conversation that can
also propose edits. ONE model call handles both:

  1. Send the WHOLE LaTeX document + the full profile + the JD + the recent conversation.
  2. The model replies conversationally, and — only when the user actually asked for a
     change — also returns a MINIMAL find/replace edit list plus a plain-English summary.
  3. Edits apply on anchors unique in the whole document, then recompile.
  4. The result is returned as a PROPOSAL. The caller shows it; the user applies it.

WHY THE WHOLE DOCUMENT (this replaced a \\section{...} router):
The old path regex-split the LaTeX, asked a small model to pick ONE section label, and sent
only that block. It broke in every direction: templates name sections differently
("Experience" vs "Work Experience" vs "Employment"), custom macros aren't \\section at all,
a theme change renamed everything, and a request spanning two sections had nowhere to go.
Worse, the model was shown a SECTION but its anchors were checked for uniqueness against the
FULL document — it was judged on information it was never given, so edits failed for reasons
it could not see. Sending the whole document removes the router, the label matching, and
that mismatch in one move: the model sees exactly what the anchor check sees, and identifies
the target by CONTENT rather than by a section name that may not exist.

GROUNDING: this path has no fact-check judge behind it (LLM.md fast-edit path), so the full
profile is the prompt's fact set and the user reviews every change before it lands.

HTTP-agnostic (BACKEND.md §0 rule 1).
"""
import json
import logging

from app.core.config import get_settings
from app.services.ai_client import structured_json
from app.services.guardrails import ats_sanitize, count_pages
from app.services.latex_service import compile_latex_async
from app.utils.analytics import request_metrics
from app.utils.edits import apply_edits
from app.utils.errors import LatexCompileError

logger = logging.getLogger("resume_edit")

# Recent conversation turns passed to the model. Capped so a long session can't grow the
# prompt without bound; matches the cap profile_ai uses for its own chat history.
_HISTORY_TURNS = 8

# JD characters included as relevance context.
_JD_EXCERPT = 1500

# Result kinds returned to the caller (and on to the frontend).
KIND_ANSWER = "answer"      # pure conversation — nothing to change
KIND_PROPOSAL = "proposal"  # edits applied + compiled, awaiting the user's approval
KIND_FAILED = "failed"      # a change was intended but could not be produced

_SYSTEM = """You are a resume assistant. The user has just generated a tailored resume and is
now talking to you about it. You can DISCUSS it and you can CHANGE it.

You are given the COMPLETE LaTeX document, the candidate's full PROFILE, the target JOB, and
the recent conversation.

DECIDE WHAT THE USER WANTS:
- A QUESTION or a comment ("what am I missing for this role?", "is my summary strong?",
  "what does this job want?", "thanks") -> just answer it. Return an EMPTY edits list.
  Be genuinely useful: compare the profile against the job, name real gaps, give concrete
  advice. This is a conversation, not a form.
- A REQUEST TO CHANGE the resume ("shorten that bullet", "add Python", "make it punchier")
  -> answer briefly AND return the edits that make it happen.
- AMBIGUOUS ("fix this", "make it better") -> do NOT guess. Ask ONE short clarifying
  question and return an EMPTY edits list. Asking is always better than a wrong edit.

WRITING EDITS (only when the user asked for a change):
Each edit is a find/replace on the LaTeX source you were given.
  - "find": an EXACT substring of the document, copied verbatim, every brace and backslash
    intact. It MUST appear EXACTLY ONCE in the WHOLE document — you can see the whole
    document, so check. If a phrase repeats, extend it until it is unique.
  - "replace": the replacement text ("" deletes).
  - "all": true ONLY when a string legitimately repeats and every copy must change together
    (an email or URL appearing in both the \\href target and the visible label). Otherwise
    false.

THE DOCUMENT MAY USE ANY TEMPLATE:
Section names, macros, and layout vary between users and change when a theme changes. NEVER
assume a section is called "Experience" or that \\section{} is even used. Find the target by
reading the CONTENT of the document you were given.

RULES:
- Do ONLY what was asked. Change nothing else.
- Use ONLY facts from the PROFILE. Never invent a skill, tool, employer, date, title, or
  number that is not there. If the user asks you to add something absent from the profile,
  say so plainly and return an EMPTY edits list instead of writing it in.
- Keep it compilable and ATS-safe: plain ASCII, no smart quotes, no em-dashes.
- Make the SMALLEST set of edits that satisfies the request.

RETURN:
- "reply": your message to the user. Always. Conversational and specific.
- "section": a short human label for the part you changed ("Professional Summary", "first
  Experience bullet"), or "" when nothing changes.
- "summary": one short plain-English line per change, so the user can see what they are
  approving before it is applied. Empty when nothing changes.
- "edits": the edit list, or [] when nothing changes."""

_SCHEMA = {
    "type": "object",
    "properties": {
        "reply": {"type": "string"},
        "section": {"type": "string"},
        "summary": {"type": "array", "items": {"type": "string"}},
        "edits": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "find": {"type": "string"},
                    "replace": {"type": "string"},
                    "all": {
                        "type": ["boolean", "null"],
                        "description": "true = replace every occurrence (emails/links shown twice)",
                    },
                },
                "required": ["find", "replace", "all"],
                "additionalProperties": False,
            },
        },
    },
    "required": ["reply", "section", "summary", "edits"],
    "additionalProperties": False,
}


# ---- prompt assembly ------------------------------------------------------

def _history_block(history: list[dict]) -> str:
    """Render recent {role, content} turns (frontend-provided) as plain context."""
    turns = [t for t in history if (t.get("content") or "").strip()][-_HISTORY_TURNS:]
    if not turns:
        return "(no prior messages — this is the first thing the user has said)"
    return "\n".join(f"{t.get('role', 'user').upper()}: {t.get('content', '')}" for t in turns)


def _user_prompt(
    tex: str, message: str, jd: str, profile: dict, history: list[dict], retry_note: str = ""
) -> str:
    return (
        f"USER MESSAGE: {message}\n\n"
        "=== RECENT CONVERSATION (a follow-up like 'shorten it more' refers to the last "
        "change) ===\n"
        f"{_history_block(history)}\n\n"
        "=== THE COMPLETE RESUME (LaTeX — your find anchors must be unique in THIS) ===\n"
        f"{tex}\n\n"
        "=== FULL PROFILE (the ONLY allowed facts; anything absent is fabrication) ===\n"
        f"{json.dumps(profile, ensure_ascii=False, indent=2)}\n\n"
        "=== TARGET JOB (for relevance and for answering questions about the role) ===\n"
        f"{(jd or '').strip()[:_JD_EXCERPT]}"
        + (f"\n\n=== PREVIOUS ATTEMPT FAILED ===\n{retry_note}" if retry_note else "")
    )


async def _ask(
    tex: str, message: str, jd: str, profile: dict, history: list[dict], retry_note: str = ""
) -> dict:
    """One model call: conversational reply plus (optionally) an edit list."""
    settings = get_settings()
    return await structured_json(
        what="resume_edit",
        system=_SYSTEM,
        user=_user_prompt(tex, message, jd, profile, history, retry_note),
        schema=_SCHEMA,
        model=settings.edit_model,
        schema_name="resume_reply",
    )


def _anchor_report(failures: list[dict]) -> str:
    """Tell the model exactly why each anchor was rejected, so a retry can fix it."""
    lines = []
    for f in failures:
        found = f.get("occurrences", 0)
        why = "it does not appear in the document" if found == 0 else f"it appears {found} times"
        lines.append(f'- "find" was rejected because {why}: {f.get("find", "")[:200]}')
    return (
        "These anchors could not be applied. Every \"find\" must appear EXACTLY ONCE in the "
        "document — copy a longer, verbatim span until it is unique.\n" + "\n".join(lines)
    )


# ---- orchestrator ---------------------------------------------------------

async def edit_resume(
    tex: str,
    message: str,
    jd: str,
    profile: dict,
    history: list[dict] | None = None,
) -> dict:
    """Answer the user, and propose resume edits when they asked for a change.

    Returns a dict:
      kind    -> "answer" | "proposal" | "failed"
      ok      -> True unless the change was requested but could not be produced
      reply   -> the assistant's message (always present)
      section -> short label of the part changed ("" for an answer)
      summary -> plain-English lines describing each proposed change
      tex     -> proposed LaTeX (unchanged source echoed back unless kind == "proposal")
      pdf     -> compiled PDF bytes of the proposal (only when kind == "proposal")
      pages   -> page count of the proposal (only when kind == "proposal")
      warning -> e.g. "now 2 pages" (may be "")

    Nothing is applied here — the caller shows the proposal and the user approves it.
    Never raises for a normal failed edit; only AIClientError (model down) propagates.
    """
    with request_metrics("/resume/edit") as m:
        result = await _edit_impl(tex, message, jd, profile, history or [])
        m["kind"] = result["kind"]
        m["section"] = result.get("section", "")
        m["edit_ok"] = result["ok"]
        return result


def _answer(reply: str, tex: str) -> dict:
    return {"kind": KIND_ANSWER, "ok": True, "reply": reply, "section": "", "summary": [], "tex": tex}


async def _edit_impl(
    tex: str, message: str, jd: str, profile: dict, history: list[dict]
) -> dict:
    res = await _ask(tex, message, jd, profile, history)
    reply = res.get("reply") or "Done."
    edits = res.get("edits") or []

    # --- pure conversation: a question, advice, or a clarifying question back -----------
    if not edits:
        logger.info("edit answer turns=%d", len(history))
        return _answer(reply, tex)

    # --- a change was asked for: place the anchors --------------------------------------
    new_tex, failures = apply_edits(tex, edits)

    # Nothing landed at all -> one retry, telling the model exactly which anchors missed.
    # (The model can see the whole document, so a second look usually resolves it.)
    if new_tex == tex:
        logger.info("edit anchors all missed (%d) — retrying", len(failures))
        res = await _ask(tex, message, jd, profile, history, _anchor_report(failures))
        reply = res.get("reply") or reply
        edits = res.get("edits") or []
        if not edits:
            return _answer(reply, tex)
        new_tex, failures = apply_edits(tex, edits)
        if new_tex == tex:
            logger.info("edit failed: no anchor landed after retry")
            return {
                "kind": KIND_FAILED,
                "ok": False,
                "reply": "I couldn't locate that part of the resume precisely enough to change "
                "it safely, so I left it as it is. Try naming the exact wording you want "
                "changed.",
                "section": res.get("section", ""),
                "summary": [],
                "tex": tex,
            }

    # Partial application is allowed — the user reviews the result before it lands — but say
    # so, rather than silently delivering less than was asked for.
    applied = len(edits) - len(failures)
    if failures:
        logger.info("edit partial applied=%d failed=%d", applied, len(failures))
        reply += (
            f"\n\n(Note: {applied} of {len(edits)} changes were placed; "
            f"{len(failures)} couldn't be located. Review below.)"
        )

    new_tex = ats_sanitize(new_tex)
    try:
        pdf = await compile_latex_async(new_tex)
    except LatexCompileError:
        logger.info("edit broke compile section=%s", res.get("section", ""))
        return {
            "kind": KIND_FAILED,
            "ok": False,
            "reply": "That change broke the document layout, so I kept your current version. "
            "Try a smaller or more specific edit.",
            "section": res.get("section", ""),
            "summary": [],
            "tex": tex,
        }

    pages = count_pages(pdf)
    warning = "" if pages <= 1 else f"This change makes it {pages} pages."
    logger.info("edit proposal section=%s edits=%d pages=%d", res.get("section", ""), applied, pages)
    return {
        "kind": KIND_PROPOSAL,
        "ok": True,
        "reply": reply,
        "section": res.get("section", ""),
        "summary": res.get("summary") or [],
        "tex": new_tex,
        "pdf": pdf,
        "pages": pages,
        "warning": warning,
    }
