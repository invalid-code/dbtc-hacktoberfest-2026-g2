"""FastAPI application wiring: the app factory, CORS, the startup lifespan and the routers."""

from contextlib import asynccontextmanager

import asyncio
import logging

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import settings
from app.database import AsyncSessionLocal
from app.logging_config import configure_logging
from app.middleware import RequestLoggingMiddleware
from app.routers import (
    alert_router,
    pump_router,
    sensor_router,
    websocket_router,
)
from app.services import device_service, irrigation_service, pump_service

configure_logging()

logger = logging.getLogger(__name__)


def allowed_origins() -> list[str]:
    """The CORS allow-list; FRONTEND_URL holds a comma-separated list of origins."""
    origins = [origin.strip() for origin in settings.FRONTEND_URL.split(",")]
    return [origin for origin in origins if origin]


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Startup bootstrap: seed pumps 1/2/3 in FAST mode.

    The schema is owned by Alembic, so the tables must already exist
    (`alembic upgrade head`) before the app starts.

    Two background tasks run next to the API: the device poll task, which
    only starts when DEVICE_URL is configured, so the API runs without a
    microcontroller attached, and the weather task, which adjusts the pumps
    from the outside weather and climate.
    """
    async with AsyncSessionLocal() as db:
        await pump_service.ensure_pumps(db)
        await pump_service.ensure_pump_modes(db)

    poll_task = None
    if device_service.device_configured():
        poll_task = asyncio.create_task(device_service.poll_loop())
        logger.info("device polling started against %s", settings.DEVICE_URL)
    else:
        logger.info("device polling is off, no DEVICE_URL is configured")

    weather_task = None
    if settings.WEATHER_ENABLED:
        weather_task = asyncio.create_task(irrigation_service.poll_loop())
        logger.info(
            "the weather service is on, it adjusts the pumps every %s seconds",
            settings.WEATHER_POLL_INTERVAL_SECONDS,
        )
    else:
        logger.info("the weather service is off, the pumps keep their parameters")

    logger.info("the api is ready")
    yield
    for task in (poll_task, weather_task):
        if task:
            task.cancel()
            try:
                await task
            except asyncio.CancelledError:
                pass
    logger.info("the api is stopping")


app = FastAPI(lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins(),
    # Starlette forbids credentials with a wildcard origin, so the "*"
    # allow-list has to run without them
    allow_credentials=settings.FRONTEND_URL != "*",
    allow_methods=["*"],
    allow_headers=["Content-Type", "Authorization"],
)
app.add_middleware(RequestLoggingMiddleware)

app.include_router(sensor_router.router)
app.include_router(pump_router.router)
app.include_router(alert_router.router)
app.include_router(websocket_router.router)


@app.get("/health")
async def health():
    """Liveness probe."""
    return {"status": "ok"}
