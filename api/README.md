# API

The FastAPI service. It owns the database, ingests sensor readings from the
ESP32 over a WebSocket, serves the REST API the Flutter app consumes, and
optionally drives the pump modes on the device.

- [Stack](#stack)
- [Running it](#running-it)
- [Configuration](#configuration)
- [Layering](#layering)
- [Endpoints](#endpoints)
- [WebSocket](#websocket)
- [Data model](#data-model)
- [Migrations](#migrations)
- [Pump-mode polling](#pump-mode-polling)
- [Alerts](#alerts)
- [Gemini](#gemini)
- [Tests](#tests)
- [Things to know](#things-to-know)

## Stack

| Concern | Choice |
|---|---|
| Language | Python 3.14 (`api/.python-version`) |
| Web framework | FastAPI, served by uvicorn |
| Validation | Pydantic v2 + pydantic-settings |
| ORM | SQLAlchemy 2.1 async ORM |
| Database | PostgreSQL via `asyncpg` (`psycopg2` for Alembic) |
| Migrations | Alembic |
| WebSockets | `websockets` via uvicorn |
| HTTP client | `httpx` (device polling, Gemini) |
| AI | Google Gemini, `generativelanguage.googleapis.com` |
| Tests | pytest + pytest-asyncio + aiosqlite |
| Dependency manager | `uv` (`pyproject.toml` + `uv.lock`, no `requirements.txt`) |

## Running it

```powershell
cd api
uv sync --group dev
uv run alembic upgrade head
uv run uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Interactive API docs: <http://localhost:8000/docs>. Health check:
`GET /health` → `{"status": "ok"}`.

## Configuration

`api/app/config.py` reads these from the environment (and from `api/.env`,
which is git-ignored):

| Variable | Default | Meaning |
|---|---|---|
| `DB_CONN_STR` | *required* | SQLAlchemy async URL, e.g. `postgresql+asyncpg://user:pass@host/db` |
| `FRONTEND_URL` | `*` | Comma-separated CORS origin allow-list |
| `DEVICE_URL` | `""` | Base URL of the ESP32's HTTP server. Empty disables device polling |
| `DEVICE_POLL_INTERVAL_SECONDS` | `5.0` | How often the API polls the device for pump modes |
| `GEMINI_API_KEY` | `""` | Google AI Studio key. Empty makes the `/gemini/*` endpoints return 503 |
| `GEMINI_MODEL` | `gemini-3.8-flash` | Model id sent to Gemini |
| `GEMINI_TIMEOUT_SECONDS` | `30.0` | Timeout for Gemini requests |

`FRONTEND_URL=*` sets `allow_credentials=False` (Starlette forbids credentials
with a wildcard origin). Any other value sets it to `True`.

## Layering

The code follows one direction:

```
routers/  ──▶  services/  ──▶  repositories/  ──▶  models.py
   │              │                  │
   └── schemas.py  └─── business logic └─── all SQL lives here
```

- **routers/** declare the HTTP surface. They parse the request with a
  Pydantic schema, call one service function, and return. No logic, no SQL.
- **services/** hold the behaviour: alert thresholds, device polling, Gemini
  context building, and the pump-mode reconciliation.
- **repositories/** are the only place that touches the database.
- **schemas.py** holds the Pydantic request and response models.
- **models.py** holds the SQLAlchemy models.
- **modes.py** holds the shared pump-mode enum.

## Endpoints

| Method | Path | Handler | Purpose |
|---|---|---|---|
| GET | `/health` | `main.py` | Liveness probe |
| GET | `/sensor/` | `sensor_router.py` | List the sensor devices |
| GET | `/sensor/data/` | `sensor_router.py` | List every sensor reading |
| GET | `/pump/` | `pump_router.py` | List the pumps |
| GET | `/pump/mode/` | `pump_router.py` | List the desired and observed pump modes |
| PUT | `/pump/mode/` | `pump_router.py` | Set the desired mode of a pump |
| GET | `/pump/history/` | `pump_router.py` | Watering history, newest first |
| POST | `/pump/history/` | `pump_router.py` | Record water usage (called by the device) |
| GET | `/pump/usage/today` | `pump_router.py` | Litres used since local midnight |
| GET | `/alerts/` | `alert_router.py` | Alerts evaluated against the latest reading |
| GET | `/gemini/insight/` | `gemini_router.py` | AI insight about the current state |
| POST | `/gemini/ask/` | `gemini_router.py` | AI question about the greenhouse |
| WS | `/mc-ws/` | `websocket_router.py` | Device publishes readings, everyone receives them |

### Sensor readings

`GET /sensor/data/` returns the whole table:

```json
[
  {
    "id": 1,
    "moisture_level": 42,
    "humidity": 78,
    "temperature": 23.5,
    "recorded_at": "2026-10-20T16:02:11.123456",
    "sensor_id": 1,
    "garbled": false
  }
]
```

Note the name change: the device's `sensor` field is `sensor_id` in REST
responses, because that is the database column name.

### Pump modes

`GET /pump/mode/`:

```json
[
  {
    "id": 1,
    "mode": 2,
    "observed_mode": 2,
    "last_seen_at": "2026-10-20T16:02:11.123456",
    "pump_id": 1
  }
]
```

- `mode` is the **desired** mode, set by the app.
- `observed_mode` is the mode the device last reported, written by the poller.
- `last_seen_at` is when the device was last polled successfully.

`PUT /pump/mode/` takes `{"pump": 1, "pump_mode": 2}`. Both fields are
required; a missing one is a 422. The pump is created on demand if it does not
exist yet. The mode is an ordinal — see the table in the
[root README](../README.md#pump-mode-ordinals).

### Pump history

`POST /pump/history/` takes `{"liters": 0.006, "pump": 1}`. `recorded_at` is
optional and defaults to now. `GET /pump/history/` returns the entries newest
first:

```json
[
  { "id": 12, "liters": 0.006, "recorded_at": "2026-10-20T16:02:11", "pump_id": 1 }
]
```

`GET /pump/usage/today` sums the litres recorded since local midnight and
returns `{"liters": 12.5}`.

### Alerts

`GET /alerts/` returns `{"alerts": [{"message": "...", "severity": "..."}]}`.
See [Alerts](#alerts) for the rules.

## WebSocket

`/mc-ws/` is the live channel. The ESP32 connects to it and publishes
readings; the API stores each one and broadcasts it to every socket on the
channel, including the app.

Published payload:

```json
{
  "sensor": 1,
  "moisture_level": 42,
  "temperature": 23.5,
  "humidity": 78,
  "garbled": false
}
```

The handler in `routers/websocket_router.py` validates the payload against
`SensorDataRequest`, saves it, and broadcasts it. The broadcast payload
(`services/websocket_service.py`) is the stored row plus an ISO-8601
`recorded_at`; it keeps the key name `sensor`.

A malformed payload raises a Pydantic `ValidationError` that is not caught, so
it closes the connection.

## Data model

`app/models.py`, five tables:

**`sensor`** — `id`. The physical sensor devices.

**`sensor_data`** — `id`, `moisture_level` (int), `humidity` (int),
`temperature` (float), `recorded_at` (datetime), `garbled` (bool),
`sensor_id` → `sensor.id`.

**`pump`** — `id`. The pumps; seeded with 1, 2, 3 on startup.

**`pump_mode`** — `id`, `mode` (int, desired), `observed_mode` (int, nullable),
`last_seen_at` (datetime, nullable), `pump_id` → `pump.id` (unique).

**`pump_history`** — `id`, `liters` (float), `recorded_at` (datetime),
`pump_id` → `pump.id` (nullable).

### Seeding

There is no seed script. The startup lifespan in `app/main.py` does it:

1. `Base.metadata.create_all` — creates any missing tables.
2. `pump_service.ensure_pumps` — creates pumps 1, 2, 3 if missing.
3. `pump_service.ensure_pump_modes` — creates a `pump_mode` row per pump, in
   `FAST` mode.

`create_all` never alters existing tables, so Alembic stays the only way to
apply later column changes.

## Migrations

```powershell
cd api
uv run alembic upgrade head
```

The chain is linear, head is `b2c3d4e5f6a7`:

| Revision | Change |
|---|---|
| `9bafc0551a33` | Base — `sensor_data` with `moisture_level` and `water_level` |
| `8b2d48567ac2` | Drops the `users` and `refresh_tokens` tables (removes auth) |
| `226664d29595` | Adds `sensor_data.sensor` |
| `ea1d4c867711` | No-op placeholder |
| `c9318941d64b` | Creates `pump` and `sensor`; adds the `pump_mode.pump_id` and `sensor_data.sensor_id` foreign keys |
| `83b1f306fe92` | Creates `pump_history` |
| `a1f2c3d4e5f6` | Adds `sensor_data.recorded_at` |
| `b7c9d1e3f5a2` | Adds `sensor_data.temperature` |
| `d3e4f5a6b7c8` | Makes `temperature` required, adds `humidity`, drops `water_level` |
| `e5f6a7b8c9d0` | Adds `pump_mode.observed_mode` and `last_seen_at` |
| `b2c3d4e5f6a7` | Adds `sensor_data.garbled` (head) |

## Pump-mode polling

`app/services/device_service.py` reconciles the modes stored in the database
with the modes the device is actually running. It only runs when `DEVICE_URL`
is set.

Every `DEVICE_POLL_INTERVAL_SECONDS` the poller:

1. `GET {DEVICE_URL}/mode` and reads the current mode of each pump.
2. Writes those into `pump_mode.observed_mode` and `pump_mode.last_seen_at`.
3. For any pump whose observed mode differs from the desired `pump_mode.mode`,
   sends `POST {DEVICE_URL}/mode` with `{"pump": 1, "mode": "DRIP"}`.
4. Records the mode the device confirmed.

The device speaks mode **names**, the database speaks **ordinals**;
`app/modes.py` converts between them. Network failures are logged and
swallowed, so an unreachable device never takes the API down.

## Alerts

`app/services/alert_service.py` evaluates the **latest** reading only:

| Condition | Message | Severity |
|---|---|---|
| No readings at all | "No sensor readings yet" | `warning` |
| Latest reading is garbled | "Spooky sensor data detected: …" | `spooky` |
| Humidity ≤ 20 % | "Check humidity levels" | `critical` |
| Moisture ≤ 30 % | "Soil moisture is low" | `warning` |
| Reading older than 30 minutes | "Sensor readings are stale" | `warning` |

A garbled reading short-circuits everything else: the thresholds would be
judging fake numbers.

## Gemini

`app/services/gemini_service.py` builds a context summary from the latest
reading, the 6 most recent readings, the active alerts, today's water usage
and the 5 most recent waterings, then asks Gemini.

Error mapping:

| Status | Cause |
|---|---|
| 503 | `GEMINI_API_KEY` is not set |
| 400 | Gemini blocked the prompt (`promptFeedback.blockReason`) |
| 502 | Gemini failed, returned non-JSON, or returned no text |
| 504 | The request timed out |

Garbled readings are excluded from the trend line and the prompt says so
explicitly, so the model does not reason about haunted numbers.

## Tests

```powershell
cd api
uv sync --group dev
uv run pytest
```

`tests/conftest.py` points `DB_CONN_STR` at a throwaway SQLite file **before**
importing the app, so the tests never touch the configured database. It also
sets `FRONTEND_URL=*` and disables the device poll.

Fixtures:

| Fixture | Purpose |
|---|---|
| `database` | Creates the schema once per session, disposes the engine and deletes the file afterwards |
| `clean_db` | Empties every table and re-seeds pumps 1–3 in `FAST` mode, before and after each test |
| `db_session` | A database session for unit tests |
| `client` | An `httpx.AsyncClient` talking to the app in process over `ASGITransport` |

The suite covers 45 tests:

| File | Tests | What it covers |
|---|---|---|
| `test_api.py` | 12 | Every REST endpoint, the 422 on an incomplete mode update, the 404 on an unknown path |
| `test_websocket.py` | 3 | A real uvicorn server: a reading is stored and broadcast, the garbled flag survives, a malformed payload is rejected |
| `test_alert_service.py` | 8 | Every alert rule, including that a garbled reading suppresses the others and that the latest reading wins |
| `test_pump_service.py` | 8 | Pump and mode seeding, mode updates, history ordering, today's usage |
| `test_sensor_service.py` | 6 | Field persistence, the garbled flag, explicit timestamps, auto-created sensors, "latest" and "recent" ordering |
| `test_modes_and_schemas.py` | 8 | The mode order matches the microcontroller's enum, schema defaults and validation errors |

## Things to know

- **No authentication.** Every endpoint and the WebSocket are open. A JWT
  system existed and was removed in migration `8b2d48567ac2`; nothing
  replaced it. Add auth before exposing this publicly.
- **CORS is the only middleware.** No rate limiting, no request logging, no
  gzip, no HTTPS redirect.
- **`engine.echo=True`** in `app/database.py` logs every SQL statement. The
  tests turn it off; production does not.
- **`GET /sensor/data/` has no pagination.** It returns the whole table.
- **Unhandled exceptions use FastAPI's default 500 handler.** There are no
  custom exception handlers.
- **`humidity` is an `int` in the schema** but the device sends a float from
  the DHT11. Pydantic coerces it only when it has no fractional part, so a
  fractional humidity would fail validation and drop the WebSocket.
