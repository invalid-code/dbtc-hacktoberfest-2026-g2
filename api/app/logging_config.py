"""The logging setup: the level, the format and the id of the request a record belongs to."""

import json
import logging
import logging.config
from contextvars import ContextVar
from datetime import datetime, timezone
from typing import Any

from app.config import settings

REQUEST_ID_HEADER = "x-request-id"

# The id of the request being served, "-" outside of a request.
request_id: ContextVar[str] = ContextVar("request_id", default="-")


class RequestIdFilter(logging.Filter):
    """Adds the id of the current request to every record that passes through."""

    def filter(self, record: logging.LogRecord) -> bool:
        record.request_id = request_id.get()
        return True


class JsonFormatter(logging.Formatter):
    """Renders a record as a single json object, one object per line."""

    def format(self, record: logging.LogRecord) -> str:
        payload: dict[str, Any] = {
            "timestamp": datetime.fromtimestamp(
                record.created, tz=timezone.utc
            ).isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
            "request_id": getattr(record, "request_id", "-"),
        }
        if record.exc_info:
            payload["exception"] = self.formatException(record.exc_info)
        return json.dumps(payload)


def formatter_name() -> str:
    """The formatter to use, either the plain text one or the json one."""
    return "json" if settings.LOG_FORMAT == "json" else "text"


def configure_logging() -> None:
    """Send every log record to the console, in the configured format and level.

    Uvicorn's own access log is turned off because the request middleware
    logs every request with its duration and its id.
    """
    logging.config.dictConfig(
        {
            "version": 1,
            "disable_existing_loggers": False,
            "filters": {"request_id": {"()": RequestIdFilter}},
            "formatters": {
                "text": {
                    "format": (
                        "%(asctime)s %(levelname)-8s %(name)s "
                        "[%(request_id)s] %(message)s"
                    ),
                    "datefmt": "%Y-%m-%dT%H:%M:%S",
                },
                "json": {"()": JsonFormatter},
            },
            "handlers": {
                "console": {
                    "class": "logging.StreamHandler",
                    "formatter": formatter_name(),
                    "filters": ["request_id"],
                    "stream": "ext://sys.stdout",
                },
            },
            "root": {"handlers": ["console"], "level": settings.LOG_LEVEL},
            "loggers": {
                "uvicorn": {
                    "handlers": ["console"],
                    "level": settings.LOG_LEVEL,
                    "propagate": False,
                },
                "uvicorn.error": {
                    "handlers": ["console"],
                    "level": settings.LOG_LEVEL,
                    "propagate": False,
                },
                "uvicorn.access": {
                    "handlers": [],
                    "level": "WARNING",
                    "propagate": False,
                },
            },
        }
    )
