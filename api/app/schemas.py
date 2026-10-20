from datetime import datetime

from pydantic import BaseModel


class SensorDataRequest(BaseModel):
    sensor: int
    moisture_level: int
    humidity: int
    temperature: float
    recorded_at: datetime | None = None


class PumpModeRequest(BaseModel):
    pump: int
    pump_mode: int


class PumpHistoryRequest(BaseModel):
    liters: float
    recorded_at: datetime | None = None
    pump: int | None = None


class SensorResponse(BaseModel):
    id: int

    model_config = {"from_attributes": True}


class SensorDataResponse(BaseModel):
    id: int
    moisture_level: int
    humidity: int
    temperature: float
    recorded_at: datetime
    sensor_id: int

    model_config = {"from_attributes": True}


class PumpResponse(BaseModel):
    id: int

    model_config = {"from_attributes": True}


class PumpModeResponse(BaseModel):
    id: int
    mode: int
    observed_mode: int | None
    last_seen_at: datetime | None
    pump_id: int

    model_config = {"from_attributes": True}


class PumpHistoryResponse(BaseModel):
    id: int
    liters: float
    recorded_at: datetime
    pump_id: int | None

    model_config = {"from_attributes": True}


class Alert(BaseModel):
    message: str
    severity: str


class AlertsResponse(BaseModel):
    alerts: list[Alert]


class TodayUsageResponse(BaseModel):
    liters: float


class GeminiAskRequest(BaseModel):
    question: str


class GeminiInsightResponse(BaseModel):
    insight: str
    model: str


class GeminiAskResponse(BaseModel):
    answer: str
    model: str


class HealthResponse(BaseModel):
    status: str
