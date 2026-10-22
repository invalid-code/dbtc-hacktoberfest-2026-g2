"""The only layer that talks to the database for the pump activation parameters."""

from datetime import datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import PumpParameter


async def get_all_parameters(db: AsyncSession) -> list[PumpParameter]:
    """The parameters of every pump that has a row."""
    result = await db.execute(select(PumpParameter))
    return list(result.scalars().all())


async def get_parameters(
    db: AsyncSession, pump_id: int
) -> PumpParameter | None:
    """The parameters of one pump, or None when it has none yet."""
    result = await db.execute(
        select(PumpParameter).where(PumpParameter.pump_id == pump_id)
    )
    return result.scalars().first()


async def save_parameters(
    db: AsyncSession,
    pump_id: int,
    active: bool,
    moisture_threshold: int,
    activation_interval_minutes: int,
    mode: int,
    reason: str,
) -> PumpParameter:
    """Write the parameters of a pump, creating its row when it has none."""
    row = await get_parameters(db, pump_id)
    if row is None:
        row = PumpParameter(pump_id=pump_id)
        db.add(row)

    row.active = active
    row.moisture_threshold = moisture_threshold
    row.activation_interval_minutes = activation_interval_minutes
    row.mode = mode
    row.reason = reason
    row.updated_at = datetime.now()

    await db.commit()
    await db.refresh(row)
    return row
