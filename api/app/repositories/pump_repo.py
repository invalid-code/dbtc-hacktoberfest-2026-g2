from datetime import datetime, timedelta

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Pump, PumpHistory, PumpMode


async def get_all_pumps(db: AsyncSession) -> list[Pump]:
    result = await db.execute(select(Pump))
    return list(result.scalars().all())


async def get_or_create_pump(db: AsyncSession, pump_id: int) -> Pump:
    pump = await db.get(Pump, pump_id)
    if pump is None:
        pump = Pump(id=pump_id)
        db.add(pump)
        await db.flush()
    return pump


async def get_all_pump_modes(db: AsyncSession) -> list[PumpMode]:
    result = await db.execute(select(PumpMode))
    return list(result.scalars().all())


async def get_pump_mode_by_pump_id(
    db: AsyncSession, pump_id: int
) -> PumpMode | None:
    result = await db.execute(
        select(PumpMode).where(PumpMode.pump_id == pump_id)
    )
    return result.scalars().first()


async def create_or_update_pump_mode(
    db: AsyncSession,
    pump_id: int,
    mode: int,
) -> PumpMode:
    db_pump_mode = await get_pump_mode_by_pump_id(db, pump_id)

    if db_pump_mode:
        db_pump_mode.mode = mode
    else:
        db_pump_mode = PumpMode(pump_id=pump_id, mode=mode)
        db.add(db_pump_mode)

    await db.commit()
    await db.refresh(db_pump_mode)
    return db_pump_mode


async def get_pump_history(db: AsyncSession) -> list[PumpHistory]:
    result = await db.execute(
        select(PumpHistory).order_by(PumpHistory.recorded_at.desc())
    )
    return list(result.scalars().all())


async def create_pump_history(
    db: AsyncSession,
    liters: float,
    recorded_at: datetime,
    pump_id: int | None = None,
) -> PumpHistory:
    if pump_id is not None:
        await get_or_create_pump(db, pump_id)
    pump_history = PumpHistory(
        liters=liters,
        recorded_at=recorded_at,
        pump_id=pump_id,
    )
    db.add(pump_history)
    await db.commit()
    await db.refresh(pump_history)
    return pump_history


async def get_today_usage_liters(db: AsyncSession) -> float:
    start_of_day = datetime.now().replace(
        hour=0, minute=0, second=0, microsecond=0
    )
    result = await db.execute(
        select(func.coalesce(func.sum(PumpHistory.liters), 0.0)).where(
            PumpHistory.recorded_at >= start_of_day,
            PumpHistory.recorded_at < start_of_day + timedelta(days=1),
        )
    )
    return float(result.scalar_one())
