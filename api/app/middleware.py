"""The request logging middleware: every request gets an id and a log line."""

import logging
import time
import uuid

from starlette.datastructures import MutableHeaders
from starlette.types import ASGIApp, Message, Receive, Scope, Send

from app.logging_config import REQUEST_ID_HEADER, request_id

logger = logging.getLogger(__name__)


class RequestLoggingMiddleware:
    """Logs every request with its status code, its duration and its id.

    The id is put in the ``x-request-id`` header of the answer and in every
    log record the request produces, so a single request can be followed
    through the whole application.
    """

    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] == "websocket":
            await self._serve_websocket(scope, receive, send)
            return
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        request_id_value = uuid.uuid4().hex
        token = request_id.set(request_id_value)
        started = time.perf_counter()
        status_code = 500

        async def send_with_request_id(message: Message) -> None:
            nonlocal status_code
            if message["type"] == "http.response.start":
                status_code = message["status"]
                MutableHeaders(scope=message).append(
                    REQUEST_ID_HEADER, request_id_value
                )
            await send(message)

        try:
            await self.app(scope, receive, send_with_request_id)
        except Exception:
            logger.exception(
                "unhandled error while serving %s %s",
                scope.get("method"),
                scope.get("path"),
            )
            raise
        finally:
            duration_ms = (time.perf_counter() - started) * 1000
            logger.log(
                logging.INFO if status_code < 500 else logging.WARNING,
                "%s %s from %s -> %s in %.1f ms",
                scope.get("method"),
                scope.get("path"),
                self._client(scope),
                status_code,
                duration_ms,
            )
            request_id.reset(token)

    async def _serve_websocket(
        self, scope: Scope, receive: Receive, send: Send
    ) -> None:
        """Serve a websocket connection, logging when it opens and when it closes."""
        token = request_id.set(uuid.uuid4().hex)
        started = time.perf_counter()
        path = scope.get("path")

        async def send_logging_accept(message: Message) -> None:
            if message["type"] == "websocket.accept":
                logger.info("websocket %s connected from %s", path, self._client(scope))
            await send(message)

        try:
            await self.app(scope, receive, send_logging_accept)
        except Exception:
            logger.exception("unhandled error in the websocket %s", path)
            raise
        finally:
            logger.info(
                "websocket %s closed after %.1f ms",
                path,
                (time.perf_counter() - started) * 1000,
            )
            request_id.reset(token)

    @staticmethod
    def _client(scope: Scope) -> str:
        """The address of the client, as far as the server knows it."""
        client = scope.get("client")
        return client[0] if client else "-"
