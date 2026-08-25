"""Resume-assistant route (BACKEND.md §0 rule 1: thin router). Auth-guarded, per-user.

POST /resume/edit -> one turn of the post-generation conversation: answer the user, and when
they asked for a change, propose the edited resume (LaTeX + compiled PDF) for them to apply.

Stateless: the client sends the current LaTeX and the recent conversation with each call, so
follow-ups keep their context while nothing is stored server-side. The profile comes from the
user's own store — it is never sent by the browser.
"""
import base64
import logging

from fastapi import APIRouter, Depends, HTTPException

from app.api.deps import get_current_user
from app.models.resume import EditRequest, EditResponse
from app.services import profile_repo
from app.services.ai_client import AIClientError
from app.services.resume_edit_service import edit_resume

logger = logging.getLogger("resume")

router = APIRouter(prefix="/resume", tags=["resume"])


@router.post("/edit", response_model=EditResponse)
async def edit_resume_endpoint(
    request: EditRequest, user: dict = Depends(get_current_user)
) -> EditResponse:
    """Answer the user's message; propose an edited resume when they asked for a change."""
    profile = await profile_repo.get_profile(user["id"])
    if profile is None:
        raise HTTPException(status_code=409, detail="Set up your profile first.")

    try:
        result = await edit_resume(
            request.tex,
            request.message,
            request.jd,
            profile["data"],
            [t.model_dump() for t in request.history],
        )
    except AIClientError as exc:
        raise HTTPException(status_code=503, detail=str(exc))

    pdf_b64 = base64.b64encode(result["pdf"]).decode("ascii") if result.get("pdf") else None
    return EditResponse(
        kind=result["kind"],
        ok=result["ok"],
        reply=result["reply"],
        section=result.get("section", ""),
        summary=result.get("summary", []),
        tex=result.get("tex", request.tex),  # unchanged source echoed back unless proposed
        pdf=pdf_b64,
        warning=result.get("warning", ""),
    )
