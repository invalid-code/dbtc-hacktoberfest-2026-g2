import logging

import httpx
from fastapi import HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.models import SensorData
from app.repositories import pump_repo, sensor_repo
from app.services import alert_service

logger = logging.getLogger(__name__)

GEMINI_API_URL = (
    "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
)

SYSTEM_INSTRUCTION = (
    "You are a greenhouse assistant for an IoT plant monitoring system. "
    "You are given soil moisture, humidity and temperature readings together with "
    "pump usage history. Answer with short, practical advice for the grower and "
    "never invent readings that are not part of the given data."
)

INSIGHT_INSTRUCTION = (
    "Write one short paragraph that states what the readings mean, whether "
    "something needs attention right now, and the single next action to take. "
    "Stay under 80 words and only mention numbers that appear in the data."
)

RECENT_READING_COUNT = 6
RECENT_WATERING_COUNT = 5


def gemini_configured() -> bool:
    return bool(settings.GEMINI_API_KEY)


def _require_configured() -> None:
    if not gemini_configured():
        raise HTTPException(
            status_code=503,
            detail="Gemini is not configured, set GEMINI_API_KEY to enable it",
        )


def _format_reading(reading: SensorData) -> str:
    return (
        f"soil moisture {reading.moisture_level}%, humidity {reading.humidity}%, "
        f"temperature {reading.temperature} C"
    )


async def build_context(db: AsyncSession) -> str:
    """Summarise the greenhouse state so the model can reason about it."""
    latest = await sensor_repo.get_latest_sensor_data(db)
    recent = await sensor_repo.get_recent_sensor_data(db, RECENT_READING_COUNT)
    history = await pump_repo.get_pump_history(db)
    today_usage = await pump_repo.get_today_usage_liters(db)
    alerts = await alert_service.evaluate_alerts(db)

    lines: list[str] = []

    if latest is None:
        lines.append("No sensor readings have been recorded yet.")
    else:
        lines.append(
            f"Latest reading ({latest.recorded_at.isoformat(timespec='seconds')}): "
            f"{_format_reading(latest)}"
        )

    if recent:
        trend = "; ".join(
            f"{reading.moisture_level}% moisture, {reading.temperature} C"
            for reading in reversed(recent)
        )
        lines.append(f"Recent readings (oldest first): {trend}.")

    if alerts:
        alert_text = "; ".join(
            f"{alert['message']} ({alert['severity']})" for alert in alerts
        )
        lines.append(f"Active alerts: {alert_text}.")
    else:
        lines.append("Active alerts: none.")

    lines.append(f"Water used today: {today_usage:.2f} L.")

    if history:
        watering = "; ".join(
            f"{entry.liters:.2f} L at {entry.recorded_at.isoformat(timespec='seconds')}"
            for entry in history[:RECENT_WATERING_COUNT]
        )
        lines.append(f"Most recent waterings: {watering}.")

    return "\n".join(lines)


def _extract_text(payload: dict) -> str:
    """Pull the generated text out of a Gemini response."""
    for candidate in payload.get("candidates") or []:
        parts = (candidate.get("content") or {}).get("parts") or []
        text = "".join(part.get("text", "") for part in parts).strip()
        if text:
            return text

    block_reason = (payload.get("promptFeedback") or {}).get("blockReason")
    if block_reason:
        raise HTTPException(
            status_code=400,
            detail=f"Gemini rejected the prompt: {block_reason}",
        )

    finish_reason = ""
    for candidate in payload.get("candidates") or []:
        finish_reason = candidate.get("finishReason") or ""
        break
    raise HTTPException(
        status_code=502,
        detail=f"Gemini returned no text (finish reason: {finish_reason or 'unknown'})",
    )


async def _complete(client: httpx.AsyncClient, prompt: str) -> str:
    response = await client.post(
        GEMINI_API_URL.format(model=settings.GEMINI_MODEL),
        headers={"x-goog-api-key": settings.GEMINI_API_KEY},
        json={
            "systemInstruction": {"parts": [{"text": SYSTEM_INSTRUCTION}]},
            "contents": [{"role": "user", "parts": [{"text": prompt}]}],
        },
    )
    if response.status_code >= 400:
        logger.warning(
            "gemini request failed with status %s: %s",
            response.status_code,
            response.text,
        )
        raise HTTPException(status_code=502, detail="The Gemini request failed")

    try:
        payload = response.json()
    except ValueError:
        logger.warning("gemini returned a non json response")
        raise HTTPException(status_code=502, detail="The Gemini response was not valid")
    return _extract_text(payload)


async def _ask_gemini(prompt: str) -> str:
    _require_configured()

    try:
        async with httpx.AsyncClient(
            timeout=httpx.Timeout(settings.GEMINI_TIMEOUT_SECONDS)
        ) as client:
            return await _complete(client, prompt)
    except httpx.TimeoutException:
        logger.warning("gemini request timed out")
        raise HTTPException(status_code=504, detail="The Gemini request timed out")
    except httpx.RequestError:
        logger.warning("could not reach gemini", exc_info=True)
        raise HTTPException(status_code=502, detail="Could not reach Gemini")


async def generate_insight(db: AsyncSession) -> str:
    """Ask Gemini for an insight about the current greenhouse state."""
    _require_configured()
    context = await build_context(db)
    prompt = (
        f"Here is the current greenhouse state:\n{context}\n\n{INSIGHT_INSTRUCTION}"
    )
    return await _ask_gemini(prompt)


async def ask(db: AsyncSession, question: str) -> str:
    """Answer a question about the greenhouse using the current state as context."""
    _require_configured()
    context = await build_context(db)
    prompt = f"Here is the current greenhouse state:\n{context}\n\nQuestion: {question}"
    return await _ask_gemini(prompt)
