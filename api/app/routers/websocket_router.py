from fastapi import APIRouter, Depends, WebSocket, WebSocketDisconnect
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.schemas import SensorDataRequest
from app.services import sensor_service, websocket_service

router = APIRouter()


@router.websocket("/mc-ws/")
async def mc_ws(
    websocket: WebSocket,
    db: AsyncSession = Depends(get_db),
):
    await websocket_service.connect(websocket)
    try:
        while True:
            data = await websocket.receive_json()
            body = SensorDataRequest.model_validate(data)
            sensor_data = await sensor_service.save_sensor_data(body, db)
            await websocket_service.broadcast_sensor_data(sensor_data)
    except WebSocketDisconnect:
        pass
    finally:
        await websocket_service.disconnect(websocket)
