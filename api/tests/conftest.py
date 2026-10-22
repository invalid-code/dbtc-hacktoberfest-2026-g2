import os
import pathlib
import tempfile

# The tests run against a throwaway sqlite database, never the configured one.
# The environment has to be set before the application is imported so the
# engine in app.database is built for the test database.
TEST_DB_PATH = pathlib.Path(tempfile.gettempdir()) / "dbtc_api_test.db"
os.environ["DB_CONN_STR"] = f"sqlite+aiosqlite:///{TEST_DB_PATH}"
os.environ["FRONTEND_URL"] = "*"
os.environ["DEVICE_URL"] = ""
# the weather service reaches out to the internet, the tests do not
os.environ["WEATHER_ENABLED"] = "false"

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy import text

from app.database import AsyncSessionLocal, Base, engine
from app.main import app
from app.services import pump_service

engine.echo = False

TABLES = ("sensor_data", "sensor", "pump_history", "pump_mode", "pump")


async def _wipe_tables() -> None:
    async with engine.begin() as conn:
        for table in TABLES:
            await conn.execute(text(f"DELETE FROM {table}"))


@pytest_asyncio.fixture(scope="session", loop_scope="session")
async def database():
    """Create the schema once for the whole test session."""
    if TEST_DB_PATH.exists():
        TEST_DB_PATH.unlink()

    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    yield engine

    await engine.dispose()
    if TEST_DB_PATH.exists():
        TEST_DB_PATH.unlink()


@pytest_asyncio.fixture(loop_scope="session")
async def clean_db(database):
    """Give every test an empty greenhouse with the default pumps."""
    await _wipe_tables()

    async with AsyncSessionLocal() as session:
        await pump_service.ensure_pumps(session)
        await pump_service.ensure_pump_modes(session)

    yield database

    await _wipe_tables()


@pytest_asyncio.fixture(loop_scope="session")
async def db_session(clean_db):
    """A database session for the unit tests."""
    async with AsyncSessionLocal() as session:
        yield session


@pytest_asyncio.fixture(loop_scope="session")
async def client(clean_db):
    """An http client talking to the application in process."""
    transport = ASGITransport(app=app)
    async with AsyncClient(
        transport=transport, base_url="http://testserver"
    ) as client:
        yield client
