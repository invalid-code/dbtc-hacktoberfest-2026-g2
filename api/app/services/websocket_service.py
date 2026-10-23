"""Keeps the set of connected sockets, broadcasts readings and pushes pump commands."""

import logging

from fastapi import WebSocket

from app.models import SensorData
from app.schemas import PumpParameterResponse

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


def _modes_payload(modes: dict[int, str]) -> dict:
    return {
        "type": "modes",
        "modes": {str(pump_id): mode for pump_id, mode in modes.items()},
    }


def _parameters_payload(
    parameters: list[PumpParameterResponse],
) -> dict:
    return {
        "type": "parameters",
        "parameters": [
            {
                "pump_id": parameter.pump_id,
                "active": parameter.active,
                "moisture_threshold": parameter.moisture_threshold,
                "activation_interval_minutes": (
                    parameter.activation_interval_minutes
                ),
            }
            for parameter in parameters
        ],
    }


async def send_pump_modes(
    websocket: WebSocket, modes: dict[int, str]
) -> None:
    """Send the modes the API wants a newly connected device to run."""
    await websocket.send_json(_modes_payload(modes))


async def send_pump_parameters(
    websocket: WebSocket, parameters: list[PumpParameterResponse]
) -> None:
    """Send the activation parameters to a newly connected device."""
    await websocket.send_json(_parameters_payload(parameters))


async def broadcast_pump_mode(pump_id: int, mode: str) -> None:
    """Tell the device that a pump switched mode so it can run it right away."""
    await _broadcast({"type": "mode", "pump": pump_id, "mode": mode})


async def broadcast_pump_parameters(
    parameters: list[PumpParameterResponse],
) -> None:
    """Send new activation parameters to every connected device."""
    await _broadcast(_parameters_payload(parameters))


async def _broadcast(payload: dict) -> None:
    disconnected: list[WebSocket] = []
    for client in active_websockets:
        try:
            await client.send_json(payload)
        except Exception:
            logger.warning(
                "a client could not receive a pump command, dropping it",
                exc_info=True,
            )
            disconnected.append(client)
    active_websockets.difference_update(disconnected)


async def connect(websocket: WebSocket) -> None:
    await websocket.accept()
    active_websockets.add(websocket)
    logger.info("%s client(s) are connected", len(active_websockets))


async def disconnect(websocket: WebSocket) -> None:
    active_websockets.discard(websocket)
    logger.info("%s client(s) are connected", len(active_websockets))
