"""Integration tests for the REST API."""

from datetime import datetime

from app.repositories import sensor_repo
from app.schemas import PumpHistoryRequest
from app.services import pump_service


async def test_the_health_check_answers(client):
    response = await client.get("/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


async def test_the_sensor_readings_are_listed(client, db_session):
    await sensor_repo.create_sensor_data(
        db=db_session,
        sensor_id=1,
        moisture_level=42,
        humidity=78,
        recorded_at=datetime(2026, 10, 31, 20, 0),
        temperature=23.5,
    )

    response = await client.get("/sensor/data/")

    assert response.status_code == 200
    readings = response.json()
    assert len(readings) == 1
    assert readings[0]["moisture_level"] == 42
    assert readings[0]["humidity"] == 78
    assert readings[0]["temperature"] == 23.5
    assert readings[0]["garbled"] is False


async def test_a_garbled_reading_is_flagged_in_the_response(client, db_session):
    await sensor_repo.create_sensor_data(
        db=db_session,
        sensor_id=1,
        moisture_level=666,
        humidity=999,
        recorded_at=datetime(2026, 10, 31, 20, 0),
        temperature=-42.5,
        garbled=True,
    )

    response = await client.get("/sensor/data/")

    assert response.json()[0]["garbled"] is True


async def test_the_pumps_are_listed(client):
    response = await client.get("/pump/")

    assert response.status_code == 200
    assert [pump["id"] for pump in response.json()] == [1, 2, 3]


async def test_the_pump_modes_are_listed(client):
    response = await client.get("/pump/mode/")

    assert response.status_code == 200
    modes = {mode["pump_id"]: mode["mode"] for mode in response.json()}
    assert modes == {1: 0, 2: 0, 3: 0}


async def test_a_pump_mode_can_be_updated(client):
    response = await client.put("/pump/mode/", json={"pump": 1, "pump_mode": 3})

    assert response.status_code == 200
    assert response.json()["mode"] == 3
    assert response.json()["pump_id"] == 1

    listed = await client.get("/pump/mode/")
    modes = {mode["pump_id"]: mode["mode"] for mode in listed.json()}
    assert modes[1] == 3


async def test_an_incomplete_pump_mode_is_rejected(client):
    response = await client.put("/pump/mode/", json={"pump": 1})

    assert response.status_code == 422


async def test_the_pump_history_is_listed_and_extended(client, db_session):
    await pump_service.create_pump_history(
        db_session, PumpHistoryRequest(liters=3.5, pump=1)
    )

    response = await client.get("/pump/history/")

    assert response.status_code == 200
    assert [entry["liters"] for entry in response.json()] == [3.5]

    created = await client.post("/pump/history/", json={"liters": 2.0, "pump": 2})

    assert created.status_code == 200
    assert created.json()["liters"] == 2.0
    assert created.json()["pump_id"] == 2


async def test_the_usage_of_today_is_reported(client, db_session):
    await pump_service.create_pump_history(
        db_session, PumpHistoryRequest(liters=7.5)
    )

    response = await client.get("/pump/usage/today")

    assert response.status_code == 200
    assert response.json() == {"liters": 7.5}


async def test_the_alerts_are_reported(client, db_session):
    await sensor_repo.create_sensor_data(
        db=db_session,
        sensor_id=1,
        moisture_level=10,
        humidity=50,
        recorded_at=datetime.now(),
        temperature=20.0,
    )

    response = await client.get("/alerts/")

    assert response.status_code == 200
    alerts = response.json()["alerts"]
    assert alerts == [{"message": "Soil moisture is low", "severity": "warning"}]


async def test_a_garbled_reading_raises_a_spooky_alert(client, db_session):
    await sensor_repo.create_sensor_data(
        db=db_session,
        sensor_id=1,
        moisture_level=666,
        humidity=999,
        recorded_at=datetime.now(),
        temperature=-42.5,
        garbled=True,
    )

    response = await client.get("/alerts/")

    alerts = response.json()["alerts"]
    assert len(alerts) == 1
    assert alerts[0]["severity"] == "spooky"


async def test_an_unknown_endpoint_answers_not_found(client):
    response = await client.get("/does-not-exist/")

    assert response.status_code == 404
