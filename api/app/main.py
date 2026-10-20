import asyncio
import math
from datetime import datetime, timedelta

from fastapi import Depends, FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import func
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select

from app.database import AsyncSessionLocal, Base, engine, get_db
from app.models import Pump, PumpHistory, PumpMode, Sensor, SensorData
from app.schemas import PumpModeRequest, SensorDataRequest

from .config import settings

app = FastAPI()
active_websockets: set[WebSocket] = set()


def allowed_origins() -> list[str]:
    origins = [origin.strip() for origin in settings.FRONTEND_URL.split(",")]
    return [origin for origin in origins if origin]


app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins(),
    allow_credentials=settings.FRONTEND_URL != "*",
    allow_methods=["*"],
    allow_headers=["Content-Type", "Authorization"],
)


@app.on_event("startup")
async def startup():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    async with AsyncSessionLocal() as db:
        for pump_id in (1, 2, 3):
            await ensure_pump(db, pump_id)
        await db.commit()
    if settings.SIMULATE_SENSORS:
        asyncio.create_task(simulate_sensors())


@app.get("/health")
async def health():
    return {"status": "ok"}


async def ensure_sensor(db: AsyncSession, sensor_id: int) -> Sensor:
    sensor = await db.get(Sensor, sensor_id)
    if sensor is None:
        sensor = Sensor(id=sensor_id)
        db.add(sensor)
        await db.flush()
    return sensor


async def ensure_pump(db: AsyncSession, pump_id: int) -> Pump:
    pump = await db.get(Pump, pump_id)
    if pump is None:
        pump = Pump(id=pump_id)
        db.add(pump)
        await db.flush()
    return pump


def generate_temperature(recorded_at: datetime) -> float:
    hour = recorded_at.hour + recorded_at.minute / 60 + recorded_at.second / 3600
    return round(24 + 8 * math.sin(2 * math.pi * (hour - 9) / 24), 1)


async def save_sensor_data(body: SensorDataRequest, db: AsyncSession) -> SensorData:
    await ensure_sensor(db, body.sensor)
    recorded_at = body.recorded_at or datetime.now()
    new_sensor_data = SensorData(
        sensor_id=body.sensor,
        moisture_level=body.moisture_level,
        water_level=body.water_level,
        recorded_at=recorded_at,
        temperature=body.temperature
        if body.temperature is not None
        else generate_temperature(recorded_at),
    )
    db.add(new_sensor_data)
    await db.commit()
    await db.refresh(new_sensor_data)
    return new_sensor_data


async def broadcast_sensor_data(sensor_data: SensorData) -> None:
    disconnected: list[WebSocket] = []
    for client in active_websockets:
        try:
            await client.send_json(
                {
                    "sensor": sensor_data.sensor_id,
                    "moisture_level": sensor_data.moisture_level,
                    "water_level": sensor_data.water_level,
                    "temperature": sensor_data.temperature,
                    "recorded_at": sensor_data.recorded_at.isoformat(),
                }
            )
        except Exception:
            disconnected.append(client)
    active_websockets.difference_update(disconnected)


async def simulate_sensors() -> None:
    async with AsyncSessionLocal() as db:
        tick = 0
        while True:
            await asyncio.sleep(settings.SIMULATE_INTERVAL_SECONDS)
            recorded_at = datetime.now()
            body = SensorDataRequest(
                sensor=1,
                moisture_level=int(55 + 15 * math.sin(tick / 7)),
                water_level=int(55 + 20 * math.sin(tick / 11 + 1)),
                recorded_at=recorded_at,
                temperature=generate_temperature(recorded_at),
            )
            new_sensor_data = await save_sensor_data(body, db)
            await broadcast_sensor_data(new_sensor_data)
            tick += 1


@app.get("/sensor/")
async def get_sensor(db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Sensor))
    return result.scalars().all()


@app.get("/sensor-data/")
async def get_sensor_data(db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(SensorData))
    return result.scalars().all()


@app.get("/pump/")
async def get_pump(
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(Pump))
    return result.scalars().all()


@app.get("/pump-mode/")
async def get_pump_mode(
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(PumpMode))
    return result.scalars().all()


@app.put("/pump-mode/")
async def update_pump_mode(
    body: PumpModeRequest,
    db: AsyncSession = Depends(get_db),
):
    await ensure_pump(db, body.pump)
    result = await db.execute(select(PumpMode).where(PumpMode.pump_id == body.pump))
    db_pump_mode = result.scalars().first()

    if db_pump_mode:
        db_pump_mode.mode = body.pump_mode
    else:
        db_pump_mode = PumpMode(pump_id=body.pump, mode=body.pump_mode)
        db.add(db_pump_mode)

    await db.commit()
    await db.refresh(db_pump_mode)

    disconnected = []
    for websocket in active_websockets:
        try:
            await websocket.send_json(
                {"pump": db_pump_mode.pump_id, "pump_mode": db_pump_mode.mode}
            )
        except Exception:
            disconnected.append(websocket)
    active_websockets.difference_update(disconnected)
    return db_pump_mode


@app.post("/sensor-data/")
async def create_sensor_data(
    body: SensorDataRequest,
    db: AsyncSession = Depends(get_db),
):
    return await save_sensor_data(body, db)


@app.get("/pump-history/")
async def get_pump_history(db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(PumpHistory).order_by(PumpHistory.recorded_at.desc())
    )
    return result.scalars().all()


@app.get("/alerts/")
async def get_alerts(db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(SensorData).order_by(SensorData.recorded_at.desc()).limit(1)
    )
    latest = result.scalars().first()
    if latest is None:
        return {
            "alerts": [{"message": "No sensor readings yet", "severity": "warning"}]
        }

    alerts: list[dict[str, str]] = []
    if latest.water_level <= 20:
        alerts.append(
            {"message": "Check water level in reservoir", "severity": "critical"}
        )
    if latest.moisture_level <= 30:
        alerts.append({"message": "Soil moisture is low", "severity": "warning"})
    if datetime.now() - latest.recorded_at > timedelta(minutes=30):
        alerts.append({"message": "Sensor readings are stale", "severity": "warning"})
    return {"alerts": alerts}


@app.get("/usage/today/")
async def get_today_usage(db: AsyncSession = Depends(get_db)):
    start_of_day = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)
    result = await db.execute(
        select(func.coalesce(func.sum(PumpHistory.liters), 0.0)).where(
            PumpHistory.recorded_at >= start_of_day,
            PumpHistory.recorded_at < start_of_day + timedelta(days=1),
        )
    )
    return {"liters": float(result.scalar_one())}


@app.websocket("/mc-ws/")
async def mc_ws(
    websocket: WebSocket,
    db: AsyncSession = Depends(get_db),
):
    await websocket.accept()
    active_websockets.add(websocket)
    try:
        while True:
            sensor_data = await websocket.receive_json()
            sensor_data_validated = SensorDataRequest.model_validate(sensor_data)
            new_sensor_data = await save_sensor_data(sensor_data_validated, db)
            await broadcast_sensor_data(new_sensor_data)
    except WebSocketDisconnect:
        pass
    finally:
        active_websockets.discard(websocket)
