"""Read-only endpoints for the greenhouse sensors and their readings."""

from datetime import datetime

from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.schemas import (
    BucketUnit,
    SensorBucketResponse,
    SensorDataResponse,
    SensorResponse,
)
from app.services import sensor_service

router = APIRouter(prefix="/sensor", tags=["sensor"])


@router.get("/", response_model=list[SensorResponse])
async def get_sensors(db: AsyncSession = Depends(get_db)):
    """List the sensor devices the greenhouse has."""
    return await sensor_service.get_sensors(db)


@router.get(
    "/data/",
    response_model=list[SensorDataResponse] | list[SensorBucketResponse],
)
async def get_sensor_data(
    bucket: BucketUnit | None = None,
    limit: int = Query(default=100, ge=1, le=1000),
    offset: int = Query(default=0, ge=0),
    since: datetime | None = None,
    until: datetime | None = None,
    db: AsyncSession = Depends(get_db),
):
    """List the readings of the greenhouse, newest first, in pages.

    Without ``bucket`` the readings themselves are paged. With ``bucket`` the
    readings are first averaged per unit of time, so a chart asks for the
    points it draws instead of every raw reading behind them.
    """
    if bucket is None:
        return await sensor_service.get_sensor_data(
            db, limit=limit, offset=offset, since=since, until=until
        )
    return await sensor_service.get_sensor_buckets(
        db,
        unit=bucket.value,
        limit=limit,
        offset=offset,
        since=since,
        until=until,
    )
