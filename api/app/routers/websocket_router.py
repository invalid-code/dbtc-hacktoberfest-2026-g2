"""The live channel: the device publishes readings here and the API rebroadcasts them."""

import logging

from fastapi import APIRouter, Depends, WebSocket, WebSocketDisconnect
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.schemas import SensorDataRequest
from app.services import device_service, sensor_service, websocket_service

logger = logging.getLogger(__name__)

router = APIRouter()


@router.websocket("/mc-ws/")
async def mc_ws(
    websocket: WebSocket,
    db: AsyncSession = Depends(get_db),
):
    """Accepts a reading, stores it and sends it on to every connected client."""
    client = (
        f"{websocket.client.host}:{websocket.client.port}"
        if websocket.client
        else None
    )
    await device_service.register_microcontroller(db, client)
    await websocket_service.connect(websocket)
    try:
        while True:
            data = await websocket.receive_json()
            # an invalid payload raises and is not caught, which closes the connection
            body = SensorDataRequest.model_validate(data)
            sensor_data = await sensor_service.save_sensor_data(body, db)
            await websocket_service.broadcast_sensor_data(sensor_data)
    except WebSocketDisconnect:
        logger.info("the microcontroller closed the connection")
    finally:
        await websocket_service.disconnect(websocket)
