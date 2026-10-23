"""The SQLAlchemy models: the sensors, their readings, the pumps and the water they used."""

from datetime import datetime

from sqlalchemy import (
    Boolean,
    Column,
    DateTime,
    Float,
    ForeignKey,
    Integer,
    String,
)
from sqlalchemy.orm import relationship

from app.database import Base


class Sensor(Base):
    """The physical sensor devices, each owning a stream of readings."""

    __tablename__ = "sensor"

    id = Column(Integer, primary_key=True, index=True)

    data_entries = relationship("SensorData", back_populates="sensor")


class SensorData(Base):
    """One greenhouse reading: moisture, humidity and temperature at a point in time."""

    __tablename__ = "sensor_data"

    id = Column(Integer, primary_key=True, index=True)
    moisture_level = Column(Integer, nullable=False)
    humidity = Column(Integer, nullable=False)
    recorded_at = Column(DateTime, nullable=False, index=True)
    temperature: Column[float] = Column(Float, nullable=False)
    # the microcontroller marks the readings it garbles as a halloween easter egg
    garbled = Column(Boolean, nullable=False, default=False)

    sensor_id = Column(Integer, ForeignKey("sensor.id"), nullable=False)

    sensor = relationship("Sensor", back_populates="data_entries")


class Pump(Base):
    """The pumps of the greenhouse, seeded with the ids 1, 2 and 3."""

    __tablename__ = "pump"

    id = Column(Integer, primary_key=True, index=True)

    pump_mode = relationship("PumpMode", back_populates="pump", uselist=False)
    history_entries = relationship("PumpHistory", back_populates="pump")
    parameter = relationship("PumpParameter", back_populates="pump", uselist=False)


class PumpMode(Base):
    """The mode row of a single pump, holding both the wanted and the last reported mode."""

    __tablename__ = "pump_mode"

    id = Column(Integer, primary_key=True, index=True)
    # mode is the desired mode, observed_mode is what the device last confirmed
    # over the socket
    mode = Column(Integer, nullable=False)
    observed_mode = Column(Integer, nullable=True)
    last_seen_at = Column(DateTime, nullable=True)

    pump_id = Column(Integer, ForeignKey("pump.id"), nullable=False, unique=True)
    pump = relationship("Pump", back_populates="pump_mode")


class PumpHistory(Base):
    """The water each pump used, kept to show the watering history and the daily total."""

    __tablename__ = "pump_history"

    id = Column(Integer, primary_key=True, index=True)
    liters: Column[float] = Column(Float, nullable=False)
    recorded_at = Column(DateTime, nullable=False)

    pump_id = Column(Integer, ForeignKey("pump.id"), nullable=True)

    pump = relationship("Pump", back_populates="history_entries")


class PumpParameter(Base):
    """The activation parameters of a single pump.

    Gemini rewrites them: active says whether the pump may water at all, the
    moisture threshold is the target it waters up to, the interval says how
    often it may do so, and the mode says how fast it delivers the water.
    """

    __tablename__ = "pump_parameter"

    id = Column(Integer, primary_key=True, index=True)
    active = Column(Boolean, nullable=False, default=True)
    moisture_threshold = Column(Integer, nullable=False, default=30)
    activation_interval_minutes = Column(Integer, nullable=False, default=60)
    mode = Column(Integer, nullable=False, default=0)
    # why the parameters were changed the last time, in words
    reason = Column(String, nullable=False, default="")
    updated_at = Column(DateTime, nullable=False, default=datetime.now)

    pump_id = Column(Integer, ForeignKey("pump.id"), nullable=False, unique=True)

    pump = relationship("Pump", back_populates="parameter")
