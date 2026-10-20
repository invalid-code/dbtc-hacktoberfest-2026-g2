from sqlalchemy import Column, DateTime, Float, ForeignKey, Integer
from sqlalchemy.orm import relationship

from app.database import Base


class Sensor(Base):
    __tablename__ = "sensor"

    id = Column(Integer, primary_key=True, index=True)

    data_entries = relationship("SensorData", back_populates="sensor")


class SensorData(Base):
    __tablename__ = "sensor_data"

    id = Column(Integer, primary_key=True, index=True)
    moisture_level = Column(Integer, nullable=False)
    humidity = Column(Integer, nullable=False)
    recorded_at = Column(DateTime, nullable=False)
    temperature: Column[float] = Column(Float, nullable=False)

    sensor_id = Column(Integer, ForeignKey("sensor.id"), nullable=False)

    sensor = relationship("Sensor", back_populates="data_entries")


class Pump(Base):
    __tablename__ = "pump"

    id = Column(Integer, primary_key=True, index=True)

    pump_mode = relationship("PumpMode", back_populates="pump", uselist=False)
    history_entries = relationship("PumpHistory", back_populates="pump")


class PumpMode(Base):
    __tablename__ = "pump_mode"

    id = Column(Integer, primary_key=True, index=True)
    mode = Column(Integer, nullable=False)
    observed_mode = Column(Integer, nullable=True)
    last_seen_at = Column(DateTime, nullable=True)

    pump_id = Column(Integer, ForeignKey("pump.id"), nullable=False, unique=True)
    pump = relationship("Pump", back_populates="pump_mode")


class PumpHistory(Base):
    __tablename__ = "pump_history"

    id = Column(Integer, primary_key=True, index=True)
    liters: Column[float] = Column(Float, nullable=False)
    recorded_at = Column(DateTime, nullable=False)

    pump_id = Column(Integer, ForeignKey("pump.id"), nullable=True)

    pump = relationship("Pump", back_populates="history_entries")
