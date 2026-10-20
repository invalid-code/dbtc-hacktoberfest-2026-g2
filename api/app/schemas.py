from datetime import datetime

from pydantic import BaseModel


class SensorDataRequest(BaseModel):
    sensor: int
    moisture_level: int
    water_level: int
    recorded_at: datetime | None = None
    temperature: float | None = None


class PumpModeRequest(BaseModel):
    pump: int
    pump_mode: int


class PumpHistoryRequest(BaseModel):
    liters: float
    recorded_at: datetime | None = None
    pump: int | None = None
