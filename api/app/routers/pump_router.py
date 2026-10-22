"""Endpoints for the pumps: their modes, the water they used and today's total."""

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.schemas import (
    PumpHistoryRequest,
    PumpHistoryResponse,
    PumpModeRequest,
    PumpModeResponse,
    PumpParameterResponse,
    PumpResponse,
    TodayUsageResponse,
)
from app.services import pump_service

router = APIRouter(prefix="/pump", tags=["pump"])


@router.get("/", response_model=list[PumpResponse])
async def get_pumps(db: AsyncSession = Depends(get_db)):
    """List the pumps."""
    return await pump_service.get_pumps(db)


@router.get("/mode/", response_model=list[PumpModeResponse])
async def get_pump_modes(db: AsyncSession = Depends(get_db)):
    """List the desired and the last observed mode of every pump."""
    return await pump_service.get_pump_modes(db)


@router.put("/mode/", response_model=PumpModeResponse)
async def update_pump_mode(
    body: PumpModeRequest,
    db: AsyncSession = Depends(get_db),
):
    """Set the desired mode of a pump; the device is reconciled separately by the poller."""
    return await pump_service.update_pump_mode(db, body.pump, body.pump_mode)


@router.get("/history/", response_model=list[PumpHistoryResponse])
async def get_pump_history(db: AsyncSession = Depends(get_db)):
    """List the watering history, newest first."""
    return await pump_service.get_pump_history(db)


@router.post("/history/", response_model=PumpHistoryResponse)
async def create_pump_history(
    body: PumpHistoryRequest,
    db: AsyncSession = Depends(get_db),
):
    """Record the water a pump used."""
    return await pump_service.create_pump_history(db, body)


@router.get("/usage/today", response_model=TodayUsageResponse)
async def get_today_usage(db: AsyncSession = Depends(get_db)):
    """The litres used since local midnight."""
    liters = await pump_service.get_today_usage(db)
    return TodayUsageResponse(liters=liters)


@router.get("/parameters/", response_model=list[PumpParameterResponse])
async def get_pump_parameters(db: AsyncSession = Depends(get_db)):
    """The activation parameters of every pump, as Gemini left them."""
    return await pump_service.get_pump_parameters(db)
