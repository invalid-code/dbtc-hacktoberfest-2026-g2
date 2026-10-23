"""The live channel: readings, usage and mode changes all travel over it."""

import logging

from fastapi import APIRouter, Depends, WebSocket, WebSocketDisconnect
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.modes import mode_index_from_name, mode_name
from app.repositories import pump_repo
from app.schemas import PumpHistoryRequest, SensorDataRequest
from app.services import device_service, pump_service, sensor_service, websocket_service

logger = logging.getLogger(__name__)

router = APIRouter()


@router.websocket("/mc-ws/")
async def mc_ws(
    websocket: WebSocket,
    db: AsyncSession = Depends(get_db),
):
    """Accepts readings and usage, stores them and sends the device its commands."""
    client = (
        f"{websocket.client.host}:{websocket.client.port}"
        if websocket.client
        else None
    )
    await device_service.register_microcontroller(db, client)
    await websocket_service.connect(websocket)

    modes = {
        mode.pump_id: mode_name(mode.mode)
        for mode in await pump_service.get_pump_modes(db)
    }
    await websocket_service.send_pump_modes(websocket, modes)
    await websocket_service.send_pump_parameters(
        websocket, await pump_service.get_pump_parameters(db)
    )

    try:
        while True:
            data = await websocket.receive_json()

            if data.get("type") == "water_usage":
                body = PumpHistoryRequest.model_validate(data)
                await pump_service.create_pump_history(db, body)
                continue

            if data.get("type") == "mode_applied":
                pump_id = data.get("pump")
                mode = mode_index_from_name(str(data.get("mode", "")))
                if isinstance(pump_id, int) and mode is not None:
                    await pump_repo.record_observed_mode(
                        db, pump_id=pump_id, observed_mode=mode
                    )
                continue

            # an invalid payload raises and is not caught, which closes the connection
            body = SensorDataRequest.model_validate(data)
            sensor_data = await sensor_service.save_sensor_data(body, db)
            await websocket_service.broadcast_sensor_data(sensor_data)
    except WebSocketDisconnect:
        logger.info("the microcontroller closed the connection")
    finally:
        await websocket_service.disconnect(websocket)
