"""Endpoints that ask Gemini for advice about the greenhouse; both need GEMINI_API_KEY."""

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.database import get_db
from app.schemas import GeminiAskRequest, GeminiAskResponse, GeminiInsightResponse
from app.services import gemini_service

router = APIRouter(prefix="/gemini", tags=["gemini"])


@router.get("/insight/", response_model=GeminiInsightResponse)
async def get_insight(db: AsyncSession = Depends(get_db)):
    """An AI insight into the current state of the greenhouse."""
    insight = await gemini_service.generate_insight(db)
    return GeminiInsightResponse(insight=insight, model=settings.GEMINI_MODEL)


@router.post("/ask/", response_model=GeminiAskResponse)
async def ask_gemini(
    body: GeminiAskRequest,
    db: AsyncSession = Depends(get_db),
):
    """Ask Gemini a question about the greenhouse."""
    answer = await gemini_service.ask(db, body.question)
    return GeminiAskResponse(answer=answer, model=settings.GEMINI_MODEL)
