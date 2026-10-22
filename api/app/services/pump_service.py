"""The pump behaviour: the pumps, their modes, the watering history and today's usage."""

import logging
from datetime import datetime

from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Pump, PumpHistory, PumpMode
from app.modes import mode_litres, mode_name
from app.repositories import parameter_repo, pump_repo
from app.schemas import PumpHistoryRequest, PumpParameterResponse

logger = logging.getLogger(__name__)


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
    pump_mode = await pump_repo.create_or_update_pump_mode(db, pump_id, mode)
    logger.info("pump %s was set to %s mode", pump_id, mode_name(mode))
    return pump_mode


async def get_pump_history(db: AsyncSession) -> list[PumpHistory]:
    return await pump_repo.get_pump_history(db)


async def create_pump_history(
    db: AsyncSession,
    body: PumpHistoryRequest,
) -> PumpHistory:
    """Record a watering, taking the moment of the reading as now when none was sent."""
    recorded_at = body.recorded_at or datetime.now()
    logger.info(
        "recorded %.2f litres for pump %s",
        body.liters,
        body.pump if body.pump is not None else "-",
    )
    return await pump_repo.create_pump_history(
        db=db,
        liters=body.liters,
        recorded_at=recorded_at,
        pump_id=body.pump,
    )


async def get_today_usage(db: AsyncSession) -> float:
    return await pump_repo.get_today_usage_liters(db)


async def get_pump_parameters(db: AsyncSession) -> list[PumpParameterResponse]:
    """The activation parameters of every pump, as Gemini left them."""
    return [
        PumpParameterResponse(
            pump_id=row.pump_id,
            active=row.active,
            moisture_threshold=row.moisture_threshold,
            activation_interval_minutes=row.activation_interval_minutes,
            mode=row.mode,
            mode_liters=mode_litres(row.mode),
            reason=row.reason,
            updated_at=row.updated_at,
        )
        for row in await parameter_repo.get_all_parameters(db)
    ]
