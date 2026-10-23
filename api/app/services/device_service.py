"""Provisions the greenhouse a microcontroller controls when it connects."""

import logging

from sqlalchemy.ext.asyncio import AsyncSession

from app.services import pump_service, sensor_service

logger = logging.getLogger(__name__)


async def register_microcontroller(
    db: AsyncSession,
    client: str | None = None,
) -> None:
    """Register a microcontroller and provision the greenhouse it controls."""
    await sensor_service.ensure_sensors(db)
    await pump_service.ensure_pumps(db)
    await pump_service.ensure_pump_modes(db)
    logger.info(
        "microcontroller %s registered with sensors 1-3 and pumps 1-3",
        client or "connected",
    )
