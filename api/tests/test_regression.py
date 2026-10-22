"""Regression tests for the workflows the greenhouse app depends on.

The unit tests pin down each service on its own; these tests walk through the
REST surface the frontend uses, across sensors, pumps and alerts, so a change
that breaks the behaviour of a whole screen or device flow fails here.
"""

from datetime import datetime, timedelta

from app.repositories import sensor_repo
from app.schemas import PumpHistoryRequest
from app.services import pump_service


async def _store_reading(
    db,
    recorded_at: datetime,
    *,
    sensor: int = 1,
    moisture: int = 42,
    humidity: int = 78,
    temperature: float = 23.5,
    garbled: bool = False,
) -> None:
    await sensor_repo.create_sensor_data(
        db=db,
        sensor_id=sensor,
        moisture_level=moisture,
        humidity=humidity,
        recorded_at=recorded_at,
        temperature=temperature,
        garbled=garbled,
    )


async def test_the_dashboard_workflow(client, db_session):
    """The dashboard can read the greenhouse, switch a pump and record water."""
    pumps = await client.get("/pump/")
    assert pumps.status_code == 200
    assert [pump["id"] for pump in pumps.json()] == [1, 2, 3]

    modes = await client.get("/pump/mode/")
    assert modes.status_code == 200
    assert {mode["pump_id"]: mode["mode"] for mode in modes.json()} == {
        1: 0,
        2: 0,
        3: 0,
    }

    changed = await client.put("/pump/mode/", json={"pump": 2, "pump_mode": 3})
    assert changed.status_code == 200
    assert changed.json()["pump_id"] == 2
    assert changed.json()["mode"] == 3

    watering = await client.post(
        "/pump/history/", json={"liters": 2.5, "pump": 2}
    )
    assert watering.status_code == 200
    assert watering.json()["liters"] == 2.5
    assert watering.json()["pump_id"] == 2

    await _store_reading(db_session, datetime.now())

    latest = await client.get("/sensor/data/?limit=1")
    assert latest.status_code == 200
    assert [reading["moisture_level"] for reading in latest.json()] == [42]
    assert latest.json()[0]["humidity"] == 78
    assert latest.json()[0]["temperature"] == 23.5

    alerts = await client.get("/alerts/")
    assert alerts.status_code == 200
    assert alerts.json() == {"alerts": []}

    usage = await client.get("/pump/usage/today")
    assert usage.status_code == 200
    assert usage.json() == {"liters": 2.5}

    history = await client.get("/pump/history/")
    assert history.status_code == 200
    assert [entry["liters"] for entry in history.json()] == [2.5]

    updated_modes = await client.get("/pump/mode/")
    assert {
        mode["pump_id"]: mode["mode"] for mode in updated_modes.json()
    }[2] == 3


async def test_paging_the_readings_walks_the_history_once(client, db_session):
    """The pages a chart downloads cover every reading once, newest first."""
    for hour in range(5):
        await _store_reading(
            db_session,
            datetime(2026, 10, 31, 10 + hour),
            moisture=10 + hour,
        )

    pages = []
    for offset in (0, 2, 4):
        response = await client.get(
            f"/sensor/data/?limit=2&offset={offset}"
        )
        assert response.status_code == 200
        pages.extend(reading["moisture_level"] for reading in response.json())

    assert pages == [14, 13, 12, 11, 10]
    assert len(pages) == len(set(pages))


async def test_the_bucket_series_averages_every_sensor_field(client, db_session):
    """A chart gets one averaged point per unit, not the raw readings."""
    for hour, minute, moisture, humidity, temperature in (
        (15, 5, 40, 50, 20.0),
        (15, 25, 44, 60, 22.0),
        (16, 5, 50, 70, 24.0),
    ):
        await _store_reading(
            db_session,
            datetime(2026, 10, 31, hour, minute),
            moisture=moisture,
            humidity=humidity,
            temperature=temperature,
        )

    response = await client.get("/sensor/data/?bucket=hour")

    assert response.status_code == 200
    buckets = response.json()
    assert [bucket["start"] for bucket in buckets] == [
        "2026-10-31T16:00:00",
        "2026-10-31T15:00:00",
    ]
    assert set(buckets[0]) == {
        "start",
        "moisture_level",
        "humidity",
        "temperature",
        "readings",
    }
    assert buckets[0]["moisture_level"] == 50.0
    assert buckets[0]["readings"] == 1
    assert buckets[1]["moisture_level"] == 42.0
    assert buckets[1]["humidity"] == 55.0
    assert buckets[1]["temperature"] == 21.0
    assert buckets[1]["readings"] == 2


async def test_since_is_inclusive_and_until_is_exclusive(client, db_session):
    """The window the charts ask for has the same bounds grouped or raw."""
    for hour in (10, 11, 12):
        await _store_reading(
            db_session,
            datetime(2026, 10, 31, hour),
            moisture=hour,
        )

    raw = await client.get(
        "/sensor/data/?since=2026-10-31T11:00:00"
        "&until=2026-10-31T12:00:00"
    )
    assert [reading["moisture_level"] for reading in raw.json()] == [11]

    buckets = await client.get(
        "/sensor/data/?bucket=hour&since=2026-10-31T11:00:00"
        "&until=2026-10-31T12:00:00"
    )
    assert [bucket["start"] for bucket in buckets.json()] == [
        "2026-10-31T11:00:00"
    ]
    assert buckets.json()[0]["readings"] == 1


async def test_the_bucket_pages_do_not_overlap(client, db_session):
    """The averaged series can be paged like the raw readings."""
    for hour in (14, 15, 16, 17):
        await _store_reading(
            db_session,
            datetime(2026, 10, 31, hour),
            moisture=hour,
        )

    starts = []
    for offset in (0, 2):
        response = await client.get(
            f"/sensor/data/?bucket=hour&limit=2&offset={offset}"
        )
        assert response.status_code == 200
        starts.extend(bucket["start"] for bucket in response.json())

    assert starts == [
        "2026-10-31T17:00:00",
        "2026-10-31T16:00:00",
        "2026-10-31T15:00:00",
        "2026-10-31T14:00:00",
    ]


async def test_a_garbled_reading_hides_the_threshold_alerts(client, db_session):
    """A haunted latest reading is the only alert the app may show."""
    await _store_reading(
        db_session,
        datetime.now(),
        moisture=1,
        humidity=1,
        temperature=-40.0,
        garbled=True,
    )

    response = await client.get("/alerts/")

    assert response.status_code == 200
    alerts = response.json()["alerts"]
    assert [alert["severity"] for alert in alerts] == ["spooky"]
    assert "haunted" in alerts[0]["message"]


async def test_a_reading_that_is_just_inside_the_window_is_in_the_bucket(
    client, db_session
):
    """The edges of a bucket stay in it, so no reading is lost by filtering."""
    await _store_reading(
        db_session, datetime(2026, 10, 31, 23, 59, 59), moisture=33
    )
    await _store_reading(
        db_session, datetime(2026, 11, 1, 0, 0, 0), moisture=44
    )

    response = await client.get("/sensor/data/?bucket=day")

    buckets = response.json()
    assert [bucket["start"] for bucket in buckets] == [
        "2026-11-01T00:00:00",
        "2026-10-31T00:00:00",
    ]
    assert [bucket["moisture_level"] for bucket in buckets] == [44.0, 33.0]


async def test_the_water_usage_of_another_day_is_left_out(client, db_session):
    """Today's usage only counts the waterings of today."""
    await pump_service.create_pump_history(
        db_session,
        PumpHistoryRequest(liters=4.0, recorded_at=datetime.now()),
    )
    await pump_service.create_pump_history(
        db_session,
        PumpHistoryRequest(
            liters=100.0,
            recorded_at=datetime.now() - timedelta(days=2),
        ),
    )

    response = await client.get("/pump/usage/today")

    assert response.json() == {"liters": 4.0}
