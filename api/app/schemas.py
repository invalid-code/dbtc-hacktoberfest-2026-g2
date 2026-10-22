"""The Pydantic request and response models of the HTTP surface."""

from datetime import datetime

from pydantic import BaseModel


class SensorDataRequest(BaseModel):
    """The payload the microcontroller publishes: sensor, moisture_level, humidity, temperature.

    recorded_at is optional and defaults to the moment the service stores the
    reading, so the device does not have to keep time. garbled marks the
    readings the device makes up for the halloween easter egg.
    """

    sensor: int
    moisture_level: int
    humidity: int
    temperature: float
    recorded_at: datetime | None = None
    garbled: bool = False


class PumpModeRequest(BaseModel):
    """The mode to switch a pump to; both fields are required and the mode is an ordinal."""

    pump: int
    pump_mode: int


class PumpHistoryRequest(BaseModel):
    """A watering to record; the pump is optional and recorded_at defaults to now."""

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
    garbled: bool

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


class PumpParameterResponse(BaseModel):
    """The activation parameters of a pump, as Gemini left them."""

    pump_id: int
    active: bool
    moisture_threshold: int
    activation_interval_minutes: int
    mode: int
    mode_liters: float
    reason: str
    updated_at: datetime


class HealthResponse(BaseModel):
    status: str
