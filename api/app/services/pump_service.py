"""The pump behaviour: the pumps, their modes, the watering history and today's usage."""

from datetime import datetime

from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Pump, PumpHistory, PumpMode
from app.repositories import pump_repo
from app.schemas import PumpHistoryRequest


async def get_pumps(db: AsyncSession) -> list[Pump]:
    return await pump_repo.get_all_pumps(db)


async def ensure_pumps(db: AsyncSession, pump_ids: tuple[int, ...] = (1, 2, 3)) -> None:
    """Create the default pumps 1, 2 and 3 if they are not in the database yet."""
    for pump_id in pump_ids:
        await pump_repo.get_or_create_pump(db, pump_id)
    await db.commit()


async def get_pump_modes(db: AsyncSession) -> list[PumpMode]:
    return await pump_repo.get_all_pump_modes(db)


async def ensure_pump_modes(
    db: AsyncSession,
    pump_ids: tuple[int, ...] = (1, 2, 3),
) -> None:
    """Give the default pumps 1, 2 and 3 a mode row, in FAST mode to start with."""
    await pump_repo.ensure_pump_modes(db, pump_ids)


async def update_pump_mode(
    db: AsyncSession,
    pump_id: int,
    mode: int,
) -> PumpMode:
    await pump_repo.get_or_create_pump(db, pump_id)
    return await pump_repo.create_or_update_pump_mode(db, pump_id, mode)


async def get_pump_history(db: AsyncSession) -> list[PumpHistory]:
    return await pump_repo.get_pump_history(db)


async def create_pump_history(
    db: AsyncSession,
    body: PumpHistoryRequest,
) -> PumpHistory:
    """Record a watering, taking the moment of the reading as now when none was sent."""
    recorded_at = body.recorded_at or datetime.now()
    return await pump_repo.create_pump_history(
        db=db,
        liters=body.liters,
        recorded_at=recorded_at,
        pump_id=body.pump,
    )


async def get_today_usage(db: AsyncSession) -> float:
    return await pump_repo.get_today_usage_liters(db)
