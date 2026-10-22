"""Reconciles the pump modes stored in the database with the modes the device is running."""

import asyncio
import logging

import httpx
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.database import AsyncSessionLocal
from app.modes import INDEX_MODE, MODE_INDEX, mode_index_from_name
from app.repositories import pump_repo

logger = logging.getLogger(__name__)

DEVICE_TIMEOUT_SECONDS = 5.0


def device_configured() -> bool:
    """Whether a microcontroller is configured to be polled at all."""
    return bool(settings.DEVICE_URL)


async def fetch_modes(client: httpx.AsyncClient) -> dict[int, str]:
    """Read the mode of every pump the microcontroller is currently running."""
    response = await client.get(f"{settings.DEVICE_URL.rstrip('/')}/mode")
    response.raise_for_status()
    payload = response.json()
    modes = payload.get("modes", payload)

    observed: dict[int, str] = {}
    for raw_pump, raw_mode in modes.items():
        try:
            pump_id = int(raw_pump)
        except (TypeError, ValueError):
            continue
        # the device HTTP API speaks mode names while the database speaks
        # ordinals, so every mode is converted on the way in
        if isinstance(raw_mode, int):
            observed[pump_id] = INDEX_MODE.get(raw_mode, "")
            continue
        index = mode_index_from_name(str(raw_mode))
        if index is not None:
            observed[pump_id] = INDEX_MODE[index]
    return observed


async def push_mode(client: httpx.AsyncClient, pump_id: int, mode: int) -> str:
    """Ask the microcontroller to switch a pump to a mode."""
    response = await client.post(
        f"{settings.DEVICE_URL.rstrip('/')}/mode",
        # the device wants a mode name, the database stores the ordinal
        json={"pump": pump_id, "mode": INDEX_MODE.get(mode, "FAST")},
    )
    response.raise_for_status()
    payload = response.json()
    applied = payload.get("mode")
    if not isinstance(applied, str):
        return INDEX_MODE.get(mode, "FAST")
    index = mode_index_from_name(applied)
    return INDEX_MODE.get(index, "FAST") if index is not None else applied


async def sync_pump_modes(db: AsyncSession) -> None:
    """One poll cycle: read the device, then push any mode it is not running."""
    if not device_configured():
        return

    async with httpx.AsyncClient(timeout=DEVICE_TIMEOUT_SECONDS) as client:
        try:
            observed = await fetch_modes(client)
        except Exception:
            logger.warning("could not read pump modes from the device", exc_info=True)
            return

        await pump_repo.record_observed_modes(db, observed)

        for pump_mode in await pump_repo.get_all_pump_modes(db):
            pump_id = pump_mode.pump_id
            mode = pump_mode.mode
            current = observed.get(pump_id)
            if current is not None and MODE_INDEX.get(current) == mode:
                continue
            try:
                applied = await push_mode(client, pump_id, mode)
            except Exception:
                logger.warning("could not set mode for pump %s", pump_id, exc_info=True)
                continue
            logger.info(
                "pump %s was switched to %s mode by the device",
                pump_id,
                INDEX_MODE.get(mode, "FAST"),
            )
            await pump_repo.record_observed_mode(
                db,
                pump_id=pump_id,
                observed_mode=MODE_INDEX.get(applied, mode),
            )


async def poll_loop() -> None:
    """Poll the microcontroller for its pump modes until cancelled."""
    while True:
        try:
            async with AsyncSessionLocal() as db:
                await sync_pump_modes(db)
        except asyncio.CancelledError:
            raise
        except Exception:
            logger.exception("pump mode poll failed")
        await asyncio.sleep(settings.DEVICE_POLL_INTERVAL_SECONDS)
