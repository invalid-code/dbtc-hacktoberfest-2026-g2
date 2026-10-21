"""Unit tests for the alert rules."""

from datetime import datetime, timedelta

from app.repositories import sensor_repo
from app.services import alert_service


async def _store_reading(
    db,
    *,
    moisture_level: int = 50,
    humidity: int = 50,
    temperature: float = 22.0,
    recorded_at: datetime | None = None,
    garbled: bool = False,
) -> None:
    await sensor_repo.create_sensor_data(
        db=db,
        sensor_id=1,
        moisture_level=moisture_level,
        humidity=humidity,
        recorded_at=recorded_at or datetime.now(),
        temperature=temperature,
        garbled=garbled,
    )


async def test_without_readings_there_is_only_a_warning(db_session):
    alerts = await alert_service.evaluate_alerts(db_session)

    assert alerts == [
        {"message": "No sensor readings yet", "severity": "warning"}
    ]


async def test_a_healthy_reading_raises_nothing(db_session):
    await _store_reading(db_session)

    assert await alert_service.evaluate_alerts(db_session) == []


async def test_low_humidity_is_critical(db_session):
    await _store_reading(db_session, humidity=10)

    alerts = await alert_service.evaluate_alerts(db_session)

    assert alerts == [{"message": "Check humidity levels", "severity": "critical"}]


async def test_low_soil_moisture_is_a_warning(db_session):
    await _store_reading(db_session, moisture_level=20)

    alerts = await alert_service.evaluate_alerts(db_session)

    assert alerts == [{"message": "Soil moisture is low", "severity": "warning"}]


async def test_stale_readings_are_reported(db_session):
    await _store_reading(
        db_session, recorded_at=datetime.now() - timedelta(minutes=45)
    )

    alerts = await alert_service.evaluate_alerts(db_session)

    assert alerts == [
        {"message": "Sensor readings are stale", "severity": "warning"}
    ]


async def test_a_garbled_reading_raises_a_spooky_alert(db_session):
    await _store_reading(
        db_session, moisture_level=999, humidity=999, temperature=-40.0, garbled=True
    )

    alerts = await alert_service.evaluate_alerts(db_session)

    assert len(alerts) == 1
    assert alerts[0]["severity"] == "spooky"
    assert "haunted" in alerts[0]["message"]


async def test_a_garbled_reading_hides_the_usual_alerts(db_session):
    await _store_reading(
        db_session, moisture_level=1, humidity=1, temperature=-40.0, garbled=True
    )

    alerts = await alert_service.evaluate_alerts(db_session)

    assert [alert["severity"] for alert in alerts] == ["spooky"]


async def test_the_latest_reading_decides_the_alerts(db_session):
    await _store_reading(db_session, humidity=10)
    await _store_reading(db_session, humidity=60)

    assert await alert_service.evaluate_alerts(db_session) == []
