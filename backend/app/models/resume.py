"""Resume-assistant schemas (BACKEND.md §2 — validation only, no logic)."""
from pydantic import BaseModel, Field

from app.models.profile import ChatTurn


class EditRequest(BaseModel):
    """Body of POST /resume/edit.

    The LaTeX source is held client-side (session memory) and sent back with each call, so
    the server stays stateless. `history` carries the conversation forward — without it every
    message was a cold start and a follow-up ("shorten it more") had no referent. Both are
    session-only; the server stores neither. The profile is NOT sent by the browser — the
    backend reads it from the user's own store.
    """

    tex: str = Field(..., min_length=1, description="Current LaTeX source of the resume.")
    message: str = Field(..., min_length=1, max_length=2000, description="The user's message.")
    jd: str = Field(default="", description="Target job description (context only).")
    history: list[ChatTurn] = Field(
        default_factory=list, description="Recent chat turns (context; capped server-side)."
    )


class EditResponse(BaseModel):
    """One assistant turn. Not every message is an edit — `kind` says which this is.

    kind == "answer"   -> conversation only (a question answered, advice, or a clarifying
                          question back). `pdf` is null and `tex` echoes the source.
    kind == "proposal" -> edits were applied to a copy and compiled successfully. NOTHING has
                          been applied for the user yet: the client shows `summary` and swaps
                          in `tex`/`pdf` only when they approve.
    kind == "failed"   -> a change was intended but could not be produced; `tex` echoes the
                          unchanged source so the client's state stays valid.
    """

    kind: str = Field(..., description='"answer" | "proposal" | "failed"')
    ok: bool = Field(..., description="False only when a requested change could not be made.")
    reply: str = Field(..., description="The assistant's message (always present).")
    section: str = Field(default="", description="Short label of the part changed.")
    summary: list[str] = Field(
        default_factory=list, description="Plain-English line per proposed change."
    )
    tex: str = Field(..., description="Proposed LaTeX; unchanged source unless kind=proposal.")
    pdf: str | None = Field(default=None, description="Base64 PDF; only when kind=proposal.")
    warning: str = Field(default="", description="Non-fatal note, e.g. it is now 2 pages.")
