# API

The FastAPI service. It owns the database, ingests sensor readings from the
ESP32 over a WebSocket, serves the REST API the Flutter app consumes, adjusts
the pumps from the outside weather, and optionally drives the pump modes on the
device.

- [Stack](#stack)
- [Running it](#running-it)
- [Configuration](#configuration)
- [Logging](#logging)
- [Layering](#layering)
- [Endpoints](#endpoints)
- [WebSocket](#websocket)
- [Data model](#data-model)
- [Migrations](#migrations)
- [Pump-mode polling](#pump-mode-polling)
- [Alerts](#alerts)
- [The weather service](#the-weather-service)
- [Tests](#tests)
- [Things to know](#things-to-know)

## Stack

|      Concern       |                           Choice                           |
|--------------------|------------------------------------------------------------|
| Language           | Python 3.14 (`api/.python-version`)                        |
| Web framework      | FastAPI, served by uvicorn                                 |
| Validation         | Pydantic v2 + pydantic-settings                            |
| ORM                | SQLAlchemy 2.1 async ORM                                   |
| Database           | PostgreSQL via `asyncpg` (`psycopg2` for Alembic)          |
| Migrations         | Alembic                                                    |
| WebSockets         | `websockets` via uvicorn                                   |
| HTTP client        | `httpx` (device polling, weather, gemini)                  |
| Weather source     | Open-Meteo, `api.open-meteo.com` (no api key)              |
| AI                 | Google Gemini, `generativelanguage.googleapis.com`         |
| Tests              | pytest + pytest-asyncio + aiosqlite                        |
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

|            Variabl             |      Default       |                                Meaning                                 |
|--------------------------------|--------------------|------------------------------------------------------------------------|
| `DB_CONN_STR`                  | *required*         | SQLAlchemy async URL, e.g. `postgresql+asyncpg://user:pass@host/db`    |
| `FRONTEND_URL`                 | `*`                | Comma-separated CORS origin allow-list                                 |
| `DEVICE_URL`                   | `""`               | Base URL of the ESP32's HTTP server. Empty disables device polling     |
| `DEVICE_POLL_INTERVAL_SECONDS` | `5.0`              | How often the API polls the device for pump modes                      |
| `WEATHER_ENABLED`              | `true`             | Turns the automatic pump adjustment on                                 |
| `WEATHER_LATITUDE`             | `14.5995`          | Latitude of the greenhouse, the place the weather is asked for         |
| `WEATHER_LONGITUDE`            | `120.9842`         | Longitude of the greenhouse                                            |
| `WEATHER_POLL_INTERVAL_SECONDS`| `3600.0`           | How often the pumps are adjusted                                       |
| `WEATHER_TIMEOUT_SECONDS`      | `30.0`             | Timeout of the calls to the weather source                             |
| `WEATHER_CLIMATE_PAST_DAYS`    | `92`               | How many days of the past form the climate normal                     |
| `GEMINI_API_KEY`               | `""`               | Google AI Studio key. Empty leaves the rules in charge of the pumps   |
| `GEMINI_MODEL`                 | `gemini-3.8-flash` | Model id sent to Gemini                                                |
| `GEMINI_TIMEOUT_SECONDS`       | `30.0`             | Timeout of the calls to Gemini                                         |
| `LOG_LEVEL`                    | `INFO`             | `DEBUG`, `INFO`, `WARNING`, `ERROR` or `CRITICAL`                      |
| `LOG_FORMAT`                   | `text`             | `text` for humans, `json` for log collectors                           |

`FRONTEND_URL=*` sets `allow_credentials=False` (Starlette forbids credentials
with a wildcard origin). Any other value sets it to `True`.

`DB_CONN_STR` always names the `asyncpg` driver, because the app engine is
async and `psycopg2` is blocking-only. A host that requires TLS (Neon, for
example) asks for it with `?ssl=require`. Alembic runs synchronously, so
`alembic/env.py` swaps the driver for `psycopg2` and renames `ssl` to the
libpq spelling `sslmode`. `channel_binding=require` is a libpq feature that
`asyncpg` does not support, so it cannot be used on the app's connection.

## Logging

`app/logging_config.py` configures the standard library logging once, when
`app/main.py` is imported, so every module only has to do
`logger = logging.getLogger(__name__)`. Everything goes to the console, in the
format `LOG_FORMAT` asks for and at the level `LOG_LEVEL` sets.

The plain text format is one line per record:

```text
2026-10-22T18:36:47 INFO     app.middleware [2b1265dbcefe4f65a5a7be9b1d7868c3] GET /health from 127.0.0.1 -> 200 in 4.4 ms
```

The json format writes one object per line, with the keys `timestamp`,
`level`, `logger`, `message`, `request_id` and, when a record carries a
traceback, `exception`.

Every request gets an id. `app/middleware.py` puts it in the `x-request-id`
header of the answer and in every record the request produces, so the logs of
a request can be told apart from the logs of everything else:

```text
2026-10-22T18:36:47 INFO     app.services.pump_service [3ae970ad130045a08c39d32016f0e8fd] pump 1 was set to DRIP mode
2026-10-22T18:36:47 INFO     app.middleware [3ae970ad130045a08c39d32016f0e8fd] PUT /pump/mode/ from 127.0.0.1 -> 200 in 3.5 ms
```

The middleware logs every request with its status code and how long it took,
and logs the traceback of the errors that reach it. Uvicorn's own access log
is turned off, because it would say the same thing without the id and the
duration.

`LOG_LEVEL=DEBUG` also turns on the SQLAlchemy echo, so every statement the
engine runs is logged as well.

## Layering

The code follows one direction:

```
routers/  ──▶  services/  ──▶  repositories/  ──▶  models.py
   │               │                   │
   └── schemas.py  └─── business logic └─── all SQL lives here
```

- **routers/** declare the HTTP surface. They parse the request with a
  Pydantic schema, call one service function, and return. No logic, no SQL.
- **services/** hold the behaviour: alert thresholds, device polling, the
  weather driven pump adjustment with Gemini, and the pump-mode
  reconciliation.
- **repositories/** are the only place that touches the database.
- **schemas.py** holds the Pydantic request and response models.
- **models.py** holds the SQLAlchemy models.
- **modes.py** holds the shared pump-mode enum.
- **logging_config.py** holds the logging setup: the level, the format and the
  id of the request a record belongs to.
- **middleware.py** holds the request logging middleware.

## Endpoints

| Method |        Path         |        Handler        |                      Purpose                      |
|--------|---------------------|-----------------------|---------------------------------------------------|
| GET    | `/health`           | `main.py`             | Liveness probe                                    |
| GET    | `/sensor/`          | `sensor_router.py`    | List the sensor devices                           |
| GET    | `/sensor/data/`     | `sensor_router.py`    | List every sensor reading                         |
| GET    | `/pump/`            | `pump_router.py`      | List the pumps                                    |
| GET    | `/pump/mode/`       | `pump_router.py`      | List the desired and observed pump modes          |
| PUT    | `/pump/mode/`       | `pump_router.py`      | Set the desired mode of a pump                    |
| GET    | `/pump/history/`    | `pump_router.py`      | Watering history, newest first                    |
| POST   | `/pump/history/`    | `pump_router.py`      | Record water usage (called by the device)         |
| GET    | `/pump/usage/today` | `pump_router.py`      | Litres used since local midnight                  |
| GET    | `/pump/parameters/` | `pump_router.py`      | The activation parameters the weather service set |
| GET    | `/alerts/`          | `alert_router.py`     | Alerts evaluated against the latest reading       |
| WS     | `/mc-ws/`           | `websocket_router.py` | Device publishes readings, everyone receives them |

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

`app/models.py`, six tables:

**`sensor`** — `id`. The physical sensor devices.

**`sensor_data`** — `id`, `moisture_level` (int), `humidity` (int),
`temperature` (float), `recorded_at` (datetime), `garbled` (bool),
`sensor_id` → `sensor.id`.

**`pump`** — `id`. The pumps; seeded with 1, 2, 3 on startup.

**`pump_mode`** — `id`, `mode` (int, desired), `observed_mode` (int, nullable),
`last_seen_at` (datetime, nullable), `pump_id` → `pump.id` (unique).

**`pump_history`** — `id`, `liters` (float), `recorded_at` (datetime),
`pump_id` → `pump.id` (nullable).

**`pump_parameter`** — `id`, `moisture_threshold` (int),
`activation_interval_minutes` (int), `mode` (int), `reason` (str),
`updated_at` (datetime), `pump_id` → `pump.id` (unique). The activation
parameters the weather service wrote for the pump.

### Seeding

There is no seed script. The startup lifespan in `app/main.py` does it:

1. `pump_service.ensure_pumps` — creates pumps 1, 2, 3 if missing.
2. `pump_service.ensure_pump_modes` — creates a `pump_mode` row per pump, in
   `FAST` mode.

The lifespan never creates tables: the schema is owned by Alembic, so
`alembic upgrade head` has to be run before the app starts.

## Migrations

```powershell
cd api
uv run alembic upgrade head
```

### In CI

`.github/workflows/migrate-prod-db.yml` applies the same command to the
production database on every push to `main`. The workflow first runs the test
suite, then runs `alembic upgrade head` with `DB_CONN_STR` taken from the
`PROD_DB_CONN_STR` repository secret. The secret must hold the prod URL in
the asyncpg form, e.g.
`postgresql+asyncpg://user:password@host/database`; `alembic/env.py` swaps
the driver for `psycopg2` on its own. A push to `main` therefore never reaches
the prod database with failing tests, and the workflow can also be started by
hand from the Actions tab.

The chain has two revisions, head is `932b8d629ca2`:

|    Revision    |                                     Change                                     |
|----------------|--------------------------------------------------------------------------------|
| `843fed31fe6a` | Creates `pump`, `sensor`, `pump_history`, `pump_mode` and `sensor_data`        |
| `932b8d629ca2` | Creates `pump_parameter`, the activation parameters of the pumps (head)         |

The eleven revisions that came before `843fed31fe6a` were squashed into that
one initial migration, so the old revision ids no longer exist. A database
that was already migrated with the old chain cannot be upgraded any more:
Alembic cannot find the revision it is stamped with. Recreate such a
database, or stamp it with `uv run alembic stamp 843fed31fe6a` once its schema
is known to match the models.

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

|           Condition           |             Message              |  Severity  |
|-------------------------------|----------------------------------|------------|
| No readings at all            | "No sensor readings yet"         | `warning`  |
| Latest reading is garbled     | "Spooky sensor data detected: …" | `spooky`   |
| Humidity ≤ 20 %               | "Check humidity levels"          | `critical` |
| Moisture ≤ 30 %               | "Soil moisture is low"           | `warning`  |
| Reading older than 30 minutes | "Sensor readings are stale"      | `warning`  |

A garbled reading short-circuits everything else: the thresholds would be
judging fake numbers.

## The weather service

`app/services/weather_service.py`, `app/services/gemini_service.py` and
`app/services/irrigation_service.py` run a background task that keeps the
pumps in step with the weather. The task starts with the app, unless
`WEATHER_ENABLED` is `false`.

Every `WEATHER_POLL_INTERVAL_SECONDS` the task:

1. Reads the **weather** of the next days from Open-Meteo: the current
   temperature and humidity, and the rain, the temperatures and the
   evaporation of every forecast day.
2. Reads the **climate** of the place from Open-Meteo: the reanalysis of the
   last `WEATHER_CLIMATE_PAST_DAYS` days, which is the seasonal normal the
   forecast is compared against.
3. Reads the **state of the greenhouse**: the readings the microcontroller sent
   over the WebSocket, the last real reading of every sensor and how the soil
   moisture moved, how long ago each pump watered and how much water it used
   today.
4. Asks **Gemini** to decide, in `app/services/gemini_service.py`. It gets
   the weather, the climate, the state of every zone and the parameters the
   pumps run with now, and it answers with json only: whether each pump may
   water at all, the moisture threshold it waters at, the minutes it has to
   wait between two activations, the mode it waters in, and a sentence saying
   why.
5. Checks the answer and writes the **activation parameters** of every pump
   into `pump_parameter`.
6. Sets the mode of the pumps that changed, which the device poller then
   pushes to the microcontroller.

Both outside sources come from [Open-Meteo](https://open-meteo.com), which
needs no api key. The weather and the climate are asked for separately
because they say different things: the forecast says what the next days will
be like, the climate says what they usually are like.

### What Gemini decides on

The prompt holds the three kinds of data together: the forecast, the climate
normal and the readings of the greenhouse.

```text
The weather of the next days:
  right now 29.2 C, 74 % humidity
  day 1: 33.5 C high, 27.7 C low, 1.6 mm of rain, 4.8 mm of evaporation
  ...
The climate of the place over the last 65 days: 28.3 C on average, 10.1 mm of rain and 4.3 mm of evaporation a day
The zones of the greenhouse:
  pump 1:
    24 % soil moisture (10 minutes ago)
    78 % humidity, 29.5 C
    the soil moisture went 55, 48, 41, 35, 30, 24 %
    watered 45 minutes ago
    0.01 litres used today
```

The garbled readings of the halloween easter egg are left out of the numbers,
because their values are made up, and the zone is marked instead, so Gemini
judges the zone on the real readings only. The firmware waters by the real
readings too, so the parameters stay in step with what the pumps do.

### When Gemini is not there

`GEMINI_API_KEY` decides who is in charge:

- with a key, Gemini decides and its answer is used,
- without a key, the plain rules in `compute_parameters` decide: the demand
  is how much water the plants need compared to a usual day, higher when the
  forecast is hotter and drier than usual and lower when rain is coming,
- when Gemini cannot be reached, the rules take over for that cycle.

The rules are a safety net, not the brain. Either way the answer is clamped
into the limits before it is stored, so neither Gemini nor one strange day
can ruin the plants:

|                   Parameter                    |  Limits  |
|-------------------------------------------|----------|
| Whether the pump may water                 | yes / no |
| Moisture threshold                          | 15 – 45 % |
| Minutes between two activations             | 15 – 720  |
| Demand                                     | 0.4 – 2.5 |

`GET /pump/parameters/` shows what was decided and why:

```json
[
  {
    "pump_id": 1,
    "active": true,
    "moisture_threshold": 28,
    "activation_interval_minutes": 90,
    "mode": 1,
    "mode_liters": 0.0028,
    "reason": "the soil is dry and it stays hot, but rain is coming on Thursday",
    "updated_at": "2026-10-22T19:54:36.123456"
  }
]
```

The parameters are only written when they really change, so the logs show
what the weather did to the greenhouse. A source that cannot be read is
logged and the old parameters stay in place.

The microcontroller runs the pump in the mode it was told to, so the mode
says how much water one activation gives. The litres of each mode are
mirrored from the firmware in `app/modes.py`.

The other three fields reach the device as well: the sketch reads
`GET /pump/parameters/` every minute and waters by the threshold, the
interval and the flag the API decided. See the
[microcontroller doc](microcontroller/README.md#watering-logic).

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

|   Fixture    |                                         Purpose                                          |
|--------------|------------------------------------------------------------------------------------------|
| `database`   | Creates the schema once per session, disposes the engine and deletes the file afterwards |
| `clean_db`   | Empties every table and re-seeds pumps 1–3 in `FAST` mode, before and after each test    |
| `db_session` | A database session for unit tests                                                        |
| `client`     | An `httpx.AsyncClient` talking to the app in process over `ASGITransport`                |

The suite covers 96 tests:

|            File             | Tests |                                                    What it covers                                                    |
|-----------------------------|-------|----------------------------------------------------------------------------------------------------------------------|
| `test_api.py`               |  12   | Every REST endpoint, the 422 on an incomplete mode update, the 404 on an unknown path                                |
| `test_websocket.py`         |   3   | A real uvicorn server: a reading is stored and broadcast, the garbled flag survives, a malformed payload is rejected |
| `test_alert_service.py`     |   8   | Every alert rule, including that a garbled reading suppresses the others and that the latest reading wins            |
| `test_pump_service.py`      |   8   | Pump and mode seeding, mode updates, history ordering, today's usage                                                 |
| `test_sensor_service.py`    |   6   | Field persistence, the garbled flag, explicit timestamps, auto-created sensors, "latest" and "recent" ordering       |
| `test_modes_and_schemas.py` |   8   | The mode order matches the microcontroller's enum, schema defaults and validation errors                             |
| `test_logging.py`           |   8   | The json formatter, the request id filter, the log level, and the request and error logs of the middleware           |
| `test_weather_service.py`   |   9   | The forecast and the climate are read from the payloads of the source, and a source that fails is reported           |
| `test_irrigation_service.py`|  23   | The demand the weather brings, the limits of the parameters, the readings Gemini sees and the parameters that are written |
| `test_gemini_service.py`     |   7   | The prompt Gemini gets, the json it is asked for, and the answers it may give back                        |

## Things to know

- **No authentication.** Every endpoint and the WebSocket are open. A JWT
  system existed and was removed; the schema has no `users` or
  `refresh_tokens` tables at all. Nothing replaced it. Add auth before
  exposing this publicly.
- **CORS is the only middleware** besides the request logging one. No rate
  limiting, no gzip, no HTTPS redirect.
- **`LOG_LEVEL=DEBUG` turns on the SQL echo** in `app/database.py`, so every
  SQL statement is logged. At the default level the statements stay quiet.
- **`GET /sensor/data/` has no pagination.** It returns the whole table.
- **Unhandled exceptions use FastAPI's default 500 handler.** There are no
  custom exception handlers, but the request middleware logs the traceback.
- **`humidity` is an `int` in the schema** but the device sends a float from
  the DHT11. Pydantic coerces it only when it has no fractional part, so a
  fractional humidity would fail validation and drop the WebSocket.
- **The weather service needs the internet.** Without it the pumps keep the
  parameters they have, and the logs say that the source could not be read.
- **The firmware reads the parameters from the API.** It keeps the last ones
  it read when the API cannot be reached, and waters at its own 30 % threshold
  until the API has answered for the first time.
- **The weather service owns the pump mode.** It sets the mode of a pump
  when Gemini or the rules move it to another one, so a manual
  `PUT /pump/mode/` lasts until the next cycle.
- **Gemini decides, the code checks.** The answer is clamped into the
  limits and the mode has to be one the device knows, so an answer that
  makes no sense is thrown away and the rules decide that cycle.
