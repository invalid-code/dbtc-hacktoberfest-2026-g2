"""Endpoint exposing the alerts the latest greenhouse reading raises."""

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.schemas import AlertsResponse
from app.services import alert_service

router = APIRouter(prefix="/alerts", tags=["alerts"])


@router.get("/", response_model=AlertsResponse)
async def get_alerts(db: AsyncSession = Depends(get_db)):
    """List the alerts raised by the latest sensor reading."""
    alerts = await alert_service.evaluate_alerts(db)
    return AlertsResponse(alerts=alerts)
