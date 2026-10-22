"""Tests for the logging setup and for the request logging middleware."""

import json
import logging

import pytest
from httpx import ASGITransport, AsyncClient
from starlette.applications import Starlette
from starlette.requests import Request
from starlette.responses import JSONResponse
from starlette.routing import Route

from app.config import settings
from app.logging_config import (
    REQUEST_ID_HEADER,
    JsonFormatter,
    RequestIdFilter,
    configure_logging,
    request_id,
)
from app.middleware import RequestLoggingMiddleware


def a_record(message: str = "the pump was started") -> logging.LogRecord:
    """A log record as the formatters would receive it."""
    return logging.LogRecord(
        "app.test", logging.INFO, __file__, 1, message, None, None
    )


def test_a_record_is_formatted_as_json():
    formatter = JsonFormatter()
    record = a_record()
    record.request_id = "the-request-id"

    payload = json.loads(formatter.format(record))

    assert payload["message"] == "the pump was started"
    assert payload["level"] == "INFO"
    assert payload["logger"] == "app.test"
    assert payload["request_id"] == "the-request-id"
    assert payload["timestamp"]


def test_the_filter_adds_the_id_of_the_running_request():
    record = a_record()

    token = request_id.set("the-request-id")
    try:
        RequestIdFilter().filter(record)
    finally:
        request_id.reset(token)

    assert record.request_id == "the-request-id"


def test_the_logging_follows_the_settings(monkeypatch):
    monkeypatch.setattr(settings, "LOG_LEVEL", "DEBUG")
    monkeypatch.setattr(settings, "LOG_FORMAT", "json")

    try:
        configure_logging()

        assert logging.getLogger().level == logging.DEBUG
        assert isinstance(logging.getLogger().handlers[0].formatter, JsonFormatter)
    finally:
        monkeypatch.undo()
        configure_logging()


async def test_a_request_is_logged_with_its_id(client, caplog):
    caplog.set_level(logging.INFO)
    logger = logging.getLogger("app.middleware")
    logger.addFilter(RequestIdFilter())

    try:
        response = await client.get("/health")
    finally:
        logger.removeFilter(RequestIdFilter())

    assert response.status_code == 200

    request_id_value = response.headers[REQUEST_ID_HEADER]
    logged = [record for record in caplog.records if record.name == "app.middleware"]

    assert logged
    assert logged[-1].getMessage().startswith("GET /health")
    assert "-> 200" in logged[-1].getMessage()
    assert logged[-1].request_id == request_id_value


async def test_a_failing_request_is_logged_with_its_error(caplog):
    caplog.set_level(logging.INFO)

    async def boom(request: Request) -> JSONResponse:
        raise RuntimeError("the pump exploded")

    app = Starlette(routes=[Route("/boom", boom)])
    app.add_middleware(RequestLoggingMiddleware)

    transport = ASGITransport(app=app, raise_app_exceptions=False)
    async with AsyncClient(transport=transport, base_url="http://testserver") as client:
        response = await client.get("/boom")

    assert response.status_code == 500

    logged = [record for record in caplog.records if record.name == "app.middleware"]
    errors = [record for record in logged if record.levelno == logging.ERROR]
    failures = [record for record in logged if record.levelno == logging.WARNING]

    assert errors
    assert "unhandled error while serving GET /boom" in errors[-1].getMessage()
    assert errors[-1].exc_info is not None
    assert failures
    assert "-> 500" in failures[-1].getMessage()


@pytest.mark.parametrize("level", ["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"])
def test_every_level_is_accepted(level, monkeypatch):
    monkeypatch.setattr(settings, "LOG_LEVEL", level)

    try:
        configure_logging()

        assert logging.getLogger().level == getattr(logging, level)
    finally:
        monkeypatch.undo()
        configure_logging()
