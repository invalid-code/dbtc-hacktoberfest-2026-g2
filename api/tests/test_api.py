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


async def test_the_readings_are_paged_newest_first(client, db_session):
    for hour, moisture in ((10, 10), (11, 11), (12, 12)):
        await sensor_repo.create_sensor_data(
            db=db_session,
            sensor_id=1,
            moisture_level=moisture,
            humidity=50,
            recorded_at=datetime(2026, 10, 31, hour, 0),
            temperature=20.0,
        )

    response = await client.get("/sensor/data/?limit=2")

    assert [reading["moisture_level"] for reading in response.json()] == [12, 11]

    response = await client.get("/sensor/data/?limit=2&offset=2")

    assert [reading["moisture_level"] for reading in response.json()] == [10]


async def test_the_readings_can_be_filtered_by_time(client, db_session):
    for hour, moisture in ((10, 10), (12, 12)):
        await sensor_repo.create_sensor_data(
            db=db_session,
            sensor_id=1,
            moisture_level=moisture,
            humidity=50,
            recorded_at=datetime(2026, 10, 31, hour, 0),
            temperature=20.0,
        )

    response = await client.get(
        "/sensor/data/?since=2026-10-31T11:00:00"
    )
    assert [reading["moisture_level"] for reading in response.json()] == [12]

    response = await client.get(
        "/sensor/data/?until=2026-10-31T11:00:00"
    )
    assert [reading["moisture_level"] for reading in response.json()] == [10]


async def test_a_page_outside_the_bounds_is_rejected(client):
    response = await client.get("/sensor/data/?limit=1001")
    assert response.status_code == 422

    response = await client.get("/sensor/data/?limit=0")
    assert response.status_code == 422

    response = await client.get("/sensor/data/?offset=-1")
    assert response.status_code == 422


async def test_the_readings_are_averaged_per_bucket(client, db_session):
    for hour, minute, moisture in ((15, 5, 40), (15, 25, 44), (16, 5, 50)):
        await sensor_repo.create_sensor_data(
            db=db_session,
            sensor_id=1,
            moisture_level=moisture,
            humidity=50,
            recorded_at=datetime(2026, 10, 31, hour, minute),
            temperature=20.0,
        )

    response = await client.get("/sensor/data/?bucket=hour")

    assert response.status_code == 200
    buckets = response.json()
    assert [bucket["start"] for bucket in buckets] == [
        "2026-10-31T16:00:00",
        "2026-10-31T15:00:00",
    ]
    assert buckets[0]["moisture_level"] == 50.0
    assert buckets[1]["moisture_level"] == 42.0
    assert buckets[1]["readings"] == 2


async def test_the_buckets_are_paged(client, db_session):
    for hour in (15, 16, 17):
        await sensor_repo.create_sensor_data(
            db=db_session,
            sensor_id=1,
            moisture_level=hour,
            humidity=50,
            recorded_at=datetime(2026, 10, 31, hour, 0),
            temperature=20.0,
        )

    response = await client.get("/sensor/data/?bucket=hour&limit=1&offset=1")

    buckets = response.json()
    assert len(buckets) == 1
    assert buckets[0]["start"] == "2026-10-31T16:00:00"

    response = await client.get(
        "/sensor/data/?bucket=hour&since=2026-10-31T16:00:00"
    )

    assert [bucket["start"] for bucket in response.json()] == [
        "2026-10-31T17:00:00",
        "2026-10-31T16:00:00",
    ]


async def test_the_buckets_start_when_their_unit_starts(client, db_session):
    await sensor_repo.create_sensor_data(
        db=db_session,
        sensor_id=1,
        moisture_level=42,
        humidity=78,
        recorded_at=datetime(2026, 10, 31, 20, 15),
        temperature=23.5,
    )

    expected = {
        "minute": "2026-10-31T20:15:00",
        "hour": "2026-10-31T20:00:00",
        "day": "2026-10-31T00:00:00",
        # the 31st is a Saturday, its week starts on Monday the 26th
        "week": "2026-10-26T00:00:00",
        "month": "2026-10-01T00:00:00",
        "year": "2026-01-01T00:00:00",
    }
    for unit, start in expected.items():
        response = await client.get(f"/sensor/data/?bucket={unit}")

        assert response.status_code == 200
        assert response.json()[0]["start"] == start


async def test_an_unknown_bucket_is_rejected(client):
    response = await client.get("/sensor/data/?bucket=fortnight")

    assert response.status_code == 422


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
