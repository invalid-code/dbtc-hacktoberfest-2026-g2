"""Keeps the set of connected sockets and broadcasts readings to all of them."""

import logging

from fastapi import WebSocket

from app.models import SensorData

logger = logging.getLogger(__name__)

active_websockets: set[WebSocket] = set()


async def broadcast_sensor_data(sensor_data: SensorData) -> None:
    """Send a reading to every connected client, dropping the ones that fail to receive it."""
    disconnected: list[WebSocket] = []
    for client in active_websockets:
        try:
            await client.send_json(
                {
                    "sensor": sensor_data.sensor_id,
                    "moisture_level": sensor_data.moisture_level,
                    "humidity": sensor_data.humidity,
                    "temperature": sensor_data.temperature,
                    "recorded_at": sensor_data.recorded_at.isoformat(),
                    "garbled": sensor_data.garbled,
                }
            )
        except Exception:
            logger.warning(
                "a client could not receive the reading, dropping it", exc_info=True
            )
            disconnected.append(client)
    active_websockets.difference_update(disconnected)
    logger.info(
        "reading of sensor %s broadcast to %s client(s)",
        sensor_data.sensor_id,
        len(active_websockets),
    )


async def connect(websocket: WebSocket) -> None:
    await websocket.accept()
    active_websockets.add(websocket)
    logger.info("%s client(s) are connected", len(active_websockets))


async def disconnect(websocket: WebSocket) -> None:
    active_websockets.discard(websocket)
    logger.info("%s client(s) are connected", len(active_websockets))
