from fastapi import WebSocket

from app.models import SensorData

active_websockets: set[WebSocket] = set()


async def broadcast_sensor_data(sensor_data: SensorData) -> None:
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
                }
            )
        except Exception:
            disconnected.append(client)
    active_websockets.difference_update(disconnected)


async def connect(websocket: WebSocket) -> None:
    await websocket.accept()
    active_websockets.add(websocket)


async def disconnect(websocket: WebSocket) -> None:
    active_websockets.discard(websocket)
