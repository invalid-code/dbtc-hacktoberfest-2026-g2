"""The sensor behaviour: the sensors themselves and the readings they report."""

import logging
from datetime import datetime

from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Sensor, SensorData
from app.repositories import sensor_repo
from app.schemas import SensorDataRequest

logger = logging.getLogger(__name__)


async def get_sensors(db: AsyncSession) -> list[Sensor]:
    return await sensor_repo.get_all_sensors(db)


async def get_sensor_data(db: AsyncSession) -> list[SensorData]:
    return await sensor_repo.get_all_sensor_data(db)


async def save_sensor_data(
    body: SensorDataRequest,
    db: AsyncSession,
) -> SensorData:
    """Store a reading, falling back to now when the device sent no timestamp.

    The sensor row is created on demand, so a reading for a sensor that was
    never seen before still lands in the database.
    """
    await sensor_repo.get_or_create_sensor(db, body.sensor)
    recorded_at = body.recorded_at or datetime.now()
    logger.info(
        "sensor %s reported %s%% moisture, %s%% humidity and %.1f C%s",
        body.sensor,
        body.moisture_level,
        body.humidity,
        body.temperature,
        " (garbled)" if body.garbled else "",
    )
    return await sensor_repo.create_sensor_data(
        db=db,
        sensor_id=body.sensor,
        moisture_level=body.moisture_level,
        humidity=body.humidity,
        recorded_at=recorded_at,
        temperature=body.temperature,
        garbled=body.garbled,
    )
