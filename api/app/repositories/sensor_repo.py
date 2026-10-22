"""The only layer that talks to the database for sensors and their readings."""

from datetime import datetime
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Sensor, SensorData

# The strftime patterns that truncate a reading to the start of its unit.
# SQLite has no date_trunc, so the tests and the development database need
# the same truncation spelled with strftime.
_SQLITE_BUCKET_FORMATS = {
    "minute": "%Y-%m-%d %H:%M:00",
    "hour": "%Y-%m-%d %H:00:00",
    "day": "%Y-%m-%d 00:00:00",
    "month": "%Y-%m-01 00:00:00",
    "year": "%Y-01-01 00:00:00",
}


def _bucket_start(column, unit: str, dialect: str):
    """The SQL expression of the first moment of the unit a reading falls in.

    Postgres truncates directly; SQLite gets the same result from strftime.
    Weeks start on Monday in both, to match the charts.
    """
    if dialect != "sqlite":
        return func.date_trunc(unit, column)
    if unit == "week":
        return func.strftime("%Y-%m-%d 00:00:00", column, "weekday 0", "-6 days")
    return func.strftime(_SQLITE_BUCKET_FORMATS[unit], column)


async def get_all_sensors(db: AsyncSession) -> list[Sensor]:
    result = await db.execute(select(Sensor))
    return list(result.scalars().all())


async def get_sensor_data(
    db: AsyncSession,
    *,
    limit: int,
    offset: int = 0,
    since: datetime | None = None,
    until: datetime | None = None,
) -> list[SensorData]:
    """A page of readings, newest first."""
    query = select(SensorData)
    if since is not None:
        query = query.where(SensorData.recorded_at >= since)
    if until is not None:
        query = query.where(SensorData.recorded_at < until)
    result = await db.execute(
        query.order_by(SensorData.recorded_at.desc(), SensorData.id.desc())
        .offset(offset)
        .limit(limit)
    )
    return list(result.scalars().all())


async def get_sensor_buckets(
    db: AsyncSession,
    *,
    unit: str,
    limit: int,
    offset: int = 0,
    since: datetime | None = None,
    until: datetime | None = None,
) -> list[dict[str, Any]]:
    """A page of readings averaged per unit of time, newest bucket first.

    The windows before and after truncating are the same, so ``since`` and
    ``until`` can filter the raw readings before they are grouped.
    """
    start = _bucket_start(
        SensorData.recorded_at, unit, db.get_bind().dialect.name
    )
    query = select(
        start.label("start"),
        func.avg(SensorData.moisture_level).label("moisture_level"),
        func.avg(SensorData.humidity).label("humidity"),
        func.avg(SensorData.temperature).label("temperature"),
        func.count(SensorData.id).label("readings"),
    )
    if since is not None:
        query = query.where(SensorData.recorded_at >= since)
    if until is not None:
        query = query.where(SensorData.recorded_at < until)
    result = await db.execute(
        query.group_by(start)
        .order_by(start.desc())
        .offset(offset)
        .limit(limit)
    )
    return [dict(bucket) for bucket in result.mappings().all()]


async def get_latest_sensor_data(db: AsyncSession) -> SensorData | None:
    """The most recently recorded reading, or None when nothing was ever recorded."""
    result = await db.execute(
        select(SensorData).order_by(SensorData.recorded_at.desc()).limit(1)
    )
    return result.scalars().first()


async def get_latest_reading_per_sensor(
    db: AsyncSession,
) -> dict[int, SensorData]:
    """The most recent reading of every sensor, keyed by the sensor id."""
    newest = (
        select(
            SensorData.sensor_id,
            func.max(SensorData.recorded_at).label("recorded_at"),
        )
        .group_by(SensorData.sensor_id)
        .subquery()
    )
    result = await db.execute(
        select(SensorData).join(
            newest,
            (SensorData.sensor_id == newest.c.sensor_id)
            & (SensorData.recorded_at == newest.c.recorded_at),
        )
    )
    return {reading.sensor_id: reading for reading in result.scalars().all()}


async def get_recent_readings_per_sensor(
    db: AsyncSession, limit: int = 6
) -> dict[int, list[SensorData]]:
    """The last readings of every sensor, newest first.

    The garbled readings are left out, their numbers are made up.
    """
    position = func.row_number().over(
        partition_by=SensorData.sensor_id,
        order_by=SensorData.recorded_at.desc(),
    ).label("position")
    result = await db.execute(
        select(SensorData, position)
        .where(SensorData.garbled.is_(False))
        .order_by(SensorData.sensor_id, position)
    )

    readings: dict[int, list[SensorData]] = {}
    for reading, rank in result.all():
        if rank <= limit:
            readings.setdefault(reading.sensor_id, []).append(reading)
    return readings


async def get_recent_sensor_data(
    db: AsyncSession, limit: int = 10
) -> list[SensorData]:
    """The last readings, newest first."""
    result = await db.execute(
        select(SensorData).order_by(SensorData.recorded_at.desc()).limit(limit)
    )
    return list(result.scalars().all())


async def get_or_create_sensor(db: AsyncSession, sensor_id: int) -> Sensor:
    """The sensor row of that id, created on the fly when it is still unknown."""
    sensor = await db.get(Sensor, sensor_id)
    if sensor is None:
        sensor = Sensor(id=sensor_id)
        db.add(sensor)
        await db.flush()
    return sensor


async def create_sensor_data(
    db: AsyncSession,
    sensor_id: int,
    moisture_level: int,
    humidity: int,
    recorded_at,
    temperature: float,
    garbled: bool = False,
) -> SensorData:
    new_sensor_data = SensorData(
        sensor_id=sensor_id,
        moisture_level=moisture_level,
        humidity=humidity,
        recorded_at=recorded_at,
        temperature=temperature,
        garbled=garbled,
    )
    db.add(new_sensor_data)
    await db.commit()
    await db.refresh(new_sensor_data)
    return new_sensor_data
