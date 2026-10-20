from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.schemas import (
    PumpHistoryRequest,
    PumpHistoryResponse,
    PumpModeRequest,
    PumpModeResponse,
    PumpResponse,
    TodayUsageResponse,
)
from app.services import pump_service

router = APIRouter(prefix="/pump", tags=["pump"])


@router.get("/", response_model=list[PumpResponse])
async def get_pumps(db: AsyncSession = Depends(get_db)):
    return await pump_service.get_pumps(db)


@router.get("/mode/", response_model=list[PumpModeResponse])
async def get_pump_modes(db: AsyncSession = Depends(get_db)):
    return await pump_service.get_pump_modes(db)


@router.put("/mode/", response_model=PumpModeResponse)
async def update_pump_mode(
    body: PumpModeRequest,
    db: AsyncSession = Depends(get_db),
):
    return await pump_service.update_pump_mode(db, body.pump, body.pump_mode)


@router.get("/history/", response_model=list[PumpHistoryResponse])
async def get_pump_history(db: AsyncSession = Depends(get_db)):
    return await pump_service.get_pump_history(db)


@router.post("/history/", response_model=PumpHistoryResponse)
async def create_pump_history(
    body: PumpHistoryRequest,
    db: AsyncSession = Depends(get_db),
):
    return await pump_service.create_pump_history(db, body)


@router.get("/usage/today", response_model=TodayUsageResponse)
async def get_today_usage(db: AsyncSession = Depends(get_db)):
    liters = await pump_service.get_today_usage(db)
    return TodayUsageResponse(liters=liters)
