"""Unit tests for the sensor service and its repository."""

from datetime import datetime

from app.models import SensorData
from app.repositories import sensor_repo
from app.schemas import SensorDataRequest
from app.services import sensor_service


async def test_saving_a_reading_stores_every_field(db_session):
    body = SensorDataRequest(
        sensor=1,
        moisture_level=42,
        humidity=78,
        temperature=23.5,
    )

    stored = await sensor_service.save_sensor_data(body, db_session)

    assert isinstance(stored, SensorData)
    assert stored.sensor_id == 1
    assert stored.moisture_level == 42
    assert stored.humidity == 78
    assert stored.temperature == 23.5
    assert stored.garbled is False
    assert stored.recorded_at is not None


async def test_saving_a_reading_keeps_the_garbled_flag(db_session):
    body = SensorDataRequest(
        sensor=1,
        moisture_level=666,
        humidity=999,
        temperature=-42.5,
        garbled=True,
    )

    stored = await sensor_service.save_sensor_data(body, db_session)

    assert stored.garbled is True


async def test_saving_a_reading_keeps_the_given_timestamp(db_session):
    recorded_at = datetime(2026, 10, 31, 23, 59, 0)
    body = SensorDataRequest(
        sensor=2,
        moisture_level=10,
        humidity=20,
        temperature=5.0,
        recorded_at=recorded_at,
    )

    stored = await sensor_service.save_sensor_data(body, db_session)

    assert stored.recorded_at == recorded_at


async def test_saving_a_reading_creates_the_sensor(db_session):
    body = SensorDataRequest(
        sensor=7, moisture_level=10, humidity=20, temperature=5.0
    )

    await sensor_service.save_sensor_data(body, db_session)

    sensors = await sensor_repo.get_all_sensors(db_session)
    assert [sensor.id for sensor in sensors] == [7]


async def test_the_latest_reading_is_the_most_recent_one(db_session):
    await sensor_repo.create_sensor_data(
        db=db_session,
        sensor_id=1,
        moisture_level=10,
        humidity=20,
        recorded_at=datetime(2026, 10, 30, 8, 0),
        temperature=5.0,
    )
    await sensor_repo.create_sensor_data(
        db=db_session,
        sensor_id=1,
        moisture_level=30,
        humidity=40,
        recorded_at=datetime(2026, 10, 31, 8, 0),
        temperature=9.0,
    )

    latest = await sensor_repo.get_latest_sensor_data(db_session)

    assert latest is not None
    assert latest.moisture_level == 30


async def test_the_recent_readings_are_the_newest_ones(db_session):
    for hour in range(5):
        await sensor_repo.create_sensor_data(
            db=db_session,
            sensor_id=1,
            moisture_level=hour,
            humidity=hour,
            recorded_at=datetime(2026, 10, 31, hour, 0),
            temperature=float(hour),
        )

    recent = await sensor_repo.get_recent_sensor_data(db_session, limit=3)

    assert [reading.moisture_level for reading in recent] == [4, 3, 2]
