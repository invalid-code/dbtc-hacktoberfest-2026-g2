from datetime import datetime, timedelta

from sqlalchemy.ext.asyncio import AsyncSession

from app.models import SensorData
from app.repositories import sensor_repo


async def evaluate_alerts(db: AsyncSession) -> list[dict[str, str]]:
    latest = await sensor_repo.get_latest_sensor_data(db)
    if latest is None:
        return [{"message": "No sensor readings yet", "severity": "warning"}]

    alerts: list[dict[str, str]] = []
    if latest.humidity <= 20:
        alerts.append(
            {
                "message": "Check humidity levels",
                "severity": "critical",
            }
        )
    if latest.moisture_level <= 30:
        alerts.append(
            {"message": "Soil moisture is low", "severity": "warning"}
        )
    if datetime.now() - latest.recorded_at > timedelta(minutes=30):
        alerts.append(
            {
                "message": "Sensor readings are stale",
                "severity": "warning",
            }
        )
    return alerts
