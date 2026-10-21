"""Read-only endpoints for the greenhouse sensors and their readings."""

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.schemas import SensorDataResponse, SensorResponse
from app.services import sensor_service

router = APIRouter(prefix="/sensor", tags=["sensor"])


@router.get("/", response_model=list[SensorResponse])
async def get_sensors(db: AsyncSession = Depends(get_db)):
    """List the sensor devices the greenhouse has."""
    return await sensor_service.get_sensors(db)


@router.get("/data/", response_model=list[SensorDataResponse])
async def get_sensor_data(db: AsyncSession = Depends(get_db)):
    """List every reading ever recorded, unpaginated."""
    return await sensor_service.get_sensor_data(db)
