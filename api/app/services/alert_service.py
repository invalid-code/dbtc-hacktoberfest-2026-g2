"""Evaluates the greenhouse alerts against the latest sensor reading only."""

import logging
from datetime import datetime, timedelta

from sqlalchemy.ext.asyncio import AsyncSession

from app.models import SensorData
from app.repositories import sensor_repo

logger = logging.getLogger(__name__)

SPOOKY_ALERT_MESSAGE = (
    "Spooky sensor data detected: the greenhouse is haunted and the latest "
    "readings are unreliable"
)


async def evaluate_alerts(db: AsyncSession) -> list[dict[str, str]]:
    """Raise an alert on low humidity, low moisture or a stale reading.

    A garbled reading short-circuits the threshold alerts because its numbers
    are fake and say nothing about the greenhouse.
    """
    latest = await sensor_repo.get_latest_sensor_data(db)
    if latest is None:
        logger.info("no sensor readings yet, only the placeholder alert is raised")
        return [{"message": "No sensor readings yet", "severity": "warning"}]

    if latest.garbled:
        # garbled readings are an halloween easter egg, they say nothing about
        # the real state of the greenhouse so no other alert is raised
        logger.info("the latest reading is garbled, only the spooky alert is raised")
        return [{"message": SPOOKY_ALERT_MESSAGE, "severity": "spooky"}]

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
    if alerts:
        logger.info(
            "%s alert(s) raised: %s",
            len(alerts),
            ", ".join(alert["message"] for alert in alerts),
        )
    return alerts
