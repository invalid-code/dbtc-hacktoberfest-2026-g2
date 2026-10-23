"""Integration tests for the microcontroller websocket."""

import asyncio
import json

import httpx
import pytest
import pytest_asyncio
import uvicorn
from websockets.asyncio.client import connect

from app.main import app
from app.repositories import sensor_repo
from app.services import sensor_service


@pytest_asyncio.fixture(loop_scope="session")
async def live_server(clean_db):
    """Run the API on a real port so a websocket client can reach it."""
    config = uvicorn.Config(app, host="127.0.0.1", port=0, log_level="warning")
    server = uvicorn.Server(config)
    task = asyncio.create_task(server.serve())

    while not server.started:
        await asyncio.sleep(0.01)

    port = server.servers[0].sockets[0].getsockname()[1]
    yield f"http://127.0.0.1:{port}"

    server.should_exit = True
    await task


async def test_connecting_provisions_the_sensors(live_server, db_session):
    url = live_server.replace("http://", "ws://") + "/mc-ws/"

    assert await sensor_service.get_sensors(db_session) == []

    async with connect(url):
        pass

    sensors = await sensor_service.get_sensors(db_session)
    assert [sensor.id for sensor in sensors] == [1, 2, 3]


async def test_a_reading_is_stored_and_broadcast(live_server, db_session):
    url = live_server.replace("http://", "ws://") + "/mc-ws/"

    async with connect(url) as websocket:
        await websocket.send(
            json.dumps(
                {
                    "sensor": 1,
                    "moisture_level": 42,
                    "humidity": 78,
                    "temperature": 23.5,
                }
            )
        )
        broadcast = json.loads(await asyncio.wait_for(websocket.recv(), timeout=5))

    assert broadcast["moisture_level"] == 42
    assert broadcast["humidity"] == 78
    assert broadcast["temperature"] == 23.5
    assert broadcast["garbled"] is False
    assert "recorded_at" in broadcast

    stored = await sensor_repo.get_latest_sensor_data(db_session)
    assert stored is not None
    assert stored.moisture_level == 42
    assert stored.sensor_id == 1


async def test_a_garbled_reading_is_flagged_in_the_broadcast(live_server, db_session):
    url = live_server.replace("http://", "ws://") + "/mc-ws/"

    async with connect(url) as websocket:
        await websocket.send(
            json.dumps(
                {
                    "sensor": 1,
                    "moisture_level": 666,
                    "humidity": 999,
                    "temperature": -42.5,
                    "garbled": True,
                }
            )
        )
        broadcast = json.loads(await asyncio.wait_for(websocket.recv(), timeout=5))

    assert broadcast["garbled"] is True

    stored = await sensor_repo.get_latest_sensor_data(db_session)
    assert stored is not None
    assert stored.garbled is True


async def test_a_pump_mode_change_is_pushed_over_the_socket(live_server):
    url = live_server.replace("http://", "ws://") + "/mc-ws/"

    async with connect(url) as websocket:
        async with httpx.AsyncClient() as client:
            response = await client.put(
                f"{live_server}/pump/mode/",
                json={"pump": 2, "pump_mode": 2},
            )
        assert response.status_code == 200

        command = json.loads(await asyncio.wait_for(websocket.recv(), timeout=5))

    assert command == {"pump": 2, "mode": "DRIP"}


async def test_an_invalid_reading_is_rejected(live_server):
    url = live_server.replace("http://", "ws://") + "/mc-ws/"

    async with connect(url) as websocket:
        await websocket.send(json.dumps({"sensor": 1}))

        with pytest.raises(Exception):
            await asyncio.wait_for(websocket.recv(), timeout=5)
