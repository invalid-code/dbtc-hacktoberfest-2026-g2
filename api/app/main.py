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
    origins = [origin.strip() for origin in settings.FRONTEND_URL.split(",")]
    return [origin for origin in origins if origin]


@asynccontextmanager
async def lifespan(app: FastAPI):
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
    return {"status": "ok"}
