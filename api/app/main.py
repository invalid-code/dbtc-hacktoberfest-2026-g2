"""FastAPI application wiring: the app factory, CORS, the startup lifespan and the routers."""

from contextlib import asynccontextmanager

import asyncio

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import settings
from app.database import AsyncSessionLocal, Base, engine
from app.routers import (
    alert_router,
    gemini_router,
    pump_router,
    sensor_router,
    websocket_router,
)
from app.services import device_service, pump_service


def allowed_origins() -> list[str]:
    """The CORS allow-list; FRONTEND_URL holds a comma-separated list of origins."""
    origins = [origin.strip() for origin in settings.FRONTEND_URL.split(",")]
    return [origin for origin in origins if origin]


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Startup bootstrap: create the missing tables and seed pumps 1/2/3 in FAST mode.

    The device poll task only starts when DEVICE_URL is configured, so the API
    runs without a microcontroller attached.
    """
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    async with AsyncSessionLocal() as db:
        await pump_service.ensure_pumps(db)
        await pump_service.ensure_pump_modes(db)

    poll_task = None
    if device_service.device_configured():
        poll_task = asyncio.create_task(device_service.poll_loop())
    yield
    if poll_task:
        poll_task.cancel()
        try:
            await poll_task
        except asyncio.CancelledError:
            pass


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

app.include_router(sensor_router.router)
app.include_router(pump_router.router)
app.include_router(alert_router.router)
app.include_router(gemini_router.router)
app.include_router(websocket_router.router)


@app.get("/health")
async def health():
    """Liveness probe."""
    return {"status": "ok"}
