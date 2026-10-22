<!-- Improved compatibility of back to top link: See: https://github.com/othneildrew/Best-README-Template/pull/73 -->
<a id="readme-top"></a>
<!--
*** Thanks for checking out this README. It follows the structure of the
*** Best-README-Template by othneildrew.
*** https://github.com/othneildrew/Best-README-Template
-->



<!-- PROJECT SHIELDS -->
<!--
*** Markdown "reference style" links are used for readability.
*** The declarations live at the bottom of this document.
-->
[![Contributors][contributors-shield]][contributors-url]
[![Forks][forks-shield]][forks-url]
[![Stargazers][stars-shield]][stars-url]
[![Issues][issues-shield]][issues-url]
[![Apache License][license-shield]][license-url]



<!-- PROJECT LOGO -->
<br />
<div align="center">
  <a href="https://github.com/invalid-code/dbtc-hacktoberfest-2026-g2/tree/main/api">
    <img src="https://img.shields.io/badge/API-FastAPI-009688?style=for-the-badge" alt="API" height="40">
  </a>

  <h3 align="center">API</h3>

  <p align="center">
    The FastAPI service that owns the database, ingests sensor readings, serves the REST API and adjusts the pumps.
    <br />
    <a href="#layering"><strong>Explore the docs »</strong></a>
    <br />
    <br />
    <a href="https://github.com/invalid-code/dbtc-hacktoberfest-2026-g2/issues/new">Report Bug</a>
    &middot;
    <a href="https://github.com/invalid-code/dbtc-hacktoberfest-2026-g2/issues/new">Request Feature</a>
  </p>
</div>



<!-- TABLE OF CONTENTS -->
<details>
  <summary>Table of Contents</summary>
  <ol>
    <li>
      <a href="#about-the-project">About The Project</a>
      <ul>
        <li><a href="#built-with">Built With</a></li>
        <li><a href="#layering">Layering</a></li>
        <li><a href="#data-model">Data Model</a></li>
        <li><a href="#seeding">Seeding</a></li>
      </ul>
    </li>
    <li>
      <a href="#getting-started">Getting Started</a>
      <ul>
        <li><a href="#prerequisites">Prerequisites</a></li>
        <li><a href="#installation">Installation</a></li>
        <li><a href="#configuration">Configuration</a></li>
      </ul>
    </li>
    <li>
      <a href="#usage">Usage</a>
      <ul>
        <li><a href="#endpoints">Endpoints</a></li>
        <li><a href="#sensor-readings">Sensor Readings</a></li>
        <li><a href="#pump-modes">Pump Modes</a></li>
        <li><a href="#pump-history">Pump History</a></li>
        <li><a href="#alerts">Alerts</a></li>
        <li><a href="#websocket">WebSocket</a></li>
        <li><a href="#pump-mode-polling">Pump-Mode Polling</a></li>
        <li><a href="#the-weather-service">The Weather Service</a></li>
        <li><a href="#migrations">Migrations</a></li>
        <li><a href="#logging">Logging</a></li>
        <li><a href="#tests">Tests</a></li>
      </ul>
    </li>
    <li><a href="#roadmap">Roadmap</a></li>
    <li><a href="#contributing">Contributing</a></li>
    <li><a href="#license">License</a></li>
    <li><a href="#contact">Contact</a></li>
    <li><a href="#acknowledgments">Acknowledgments</a></li>
  </ol>
</details>



<!-- ABOUT THE PROJECT -->
## About The Project

The FastAPI service. It owns the database, ingests sensor readings from the ESP32 over a WebSocket, serves the REST API the Flutter app consumes, adjusts the pumps from the outside weather, and optionally drives the pump modes on the device.

Part of [Greenhouse IoT](../README.md). The other components are the [Flutter frontend](../frontend/README.md) and the [ESP32 firmware](../microcontroller/README.md).

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- BUILT WITH -->
### Built With

* [![Python][Python.org]][Python-url]
* [![FastAPI][FastAPI.com]][FastAPI-url]
* [![PostgreSQL][PostgreSQL.org]][PostgreSQL-url]
* [![SQLAlchemy][SQLAlchemy.org]][SQLAlchemy-url]
* [![Pydantic][Pydantic.dev]][Pydantic-url]
* [![pytest][pytest.org]][pytest-url]
* [![Google Gemini][Gemini.ai]][Gemini-url]
* [Open-Meteo](https://open-meteo.com)

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

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- LAYERING -->
### Layering

The code follows one direction:

```
routers/  ──▶  services/  ──▶  repositories/  ──▶  models.py
   │               │                   │
   └── schemas.py  └─── business logic └─── all SQL lives here
```

- **routers/** declare the HTTP surface. They parse the request with a Pydantic schema, call one service function, and return. No logic, no SQL.
- **services/** hold the behaviour: alert thresholds, device polling, the weather driven pump adjustment with Gemini, and the pump-mode reconciliation.
- **repositories/** are the only place that touches the database.
- **schemas.py** holds the Pydantic request and response models.
- **models.py** holds the SQLAlchemy models.
- **modes.py** holds the shared pump-mode enum.
- **logging_config.py** holds the logging setup: the level, the format and the id of the request a record belongs to.
- **middleware.py** holds the request logging middleware.

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- DATA MODEL -->
### Data Model

`app/models.py`, six tables:

**`sensor`** — `id`. The physical sensor devices.

**`sensor_data`** — `id`, `moisture_level` (int), `humidity` (int), `temperature` (float), `recorded_at` (datetime), `garbled` (bool), `sensor_id` → `sensor.id`.

**`pump`** — `id`. The pumps; seeded with 1, 2, 3 on startup.

**`pump_mode`** — `id`, `mode` (int, desired), `observed_mode` (int, nullable), `last_seen_at` (datetime, nullable), `pump_id` → `pump.id` (unique).

**`pump_history`** — `id`, `liters` (float), `recorded_at` (datetime), `pump_id` → `pump.id` (nullable).

**`pump_parameter`** — `id`, `moisture_threshold` (int), `activation_interval_minutes` (int), `mode` (int), `reason` (str), `updated_at` (datetime), `pump_id` → `pump.id` (unique). The activation parameters the weather service wrote for the pump.

#### Seeding

There is no seed script. The startup lifespan in `app/main.py` does it:

1. `pump_service.ensure_pumps` — creates pumps 1, 2, 3 if missing.
2. `pump_service.ensure_pump_modes` — creates a `pump_mode` row per pump, in `FAST` mode.

The lifespan never creates tables: the schema is owned by Alembic, so `alembic upgrade head` has to be run before the app starts.

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- GETTING STARTED -->
## Getting Started

To get the service up and running locally, follow these steps.

### Prerequisites

* [Python 3.14+](https://www.python.org) — the runtime (`api/.python-version`)
* [uv](https://docs.astral.sh/uv/) — the dependency manager
* [PostgreSQL](https://www.postgresql.org) — the database
* A [Google AI Studio](https://aistudio.google.com) API key (optional) — lets Gemini decide how the pumps behave
* Internet access (optional) — the weather service reads Open-Meteo

### Installation

```powershell
cd api
uv sync --group dev
uv run alembic upgrade head
uv run uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Interactive API docs: <http://localhost:8000/docs>. Health check: `GET /health` → `{"status": "ok"}`.

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- CONFIGURATION -->
### Configuration

`api/app/config.py` reads these from the environment (and from `api/.env`, which is git-ignored):

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

`FRONTEND_URL=*` sets `allow_credentials=False` (Starlette forbids credentials with a wildcard origin). Any other value sets it to `True`.

`DB_CONN_STR` always names the `asyncpg` driver, because the app engine is async and `psycopg2` is blocking-only. A host that requires TLS (Neon, for example) asks for it with `?ssl=require`. Alembic runs synchronously, so `alembic/env.py` swaps the driver for `psycopg2` and renames `ssl` to the libpq spelling `sslmode`. `channel_binding=require` is a libpq feature that `asyncpg` does not support, so it cannot be used on the app's connection.

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- USAGE -->
## Usage

### Endpoints

| Method |        Path         |        Handler        |                      Purpose                      |
|--------|---------------------|-----------------------|---------------------------------------------------|
| GET    | `/health`           | `main.py`             | Liveness probe                                    |
| GET    | `/sensor/`          | `sensor_router.py`    | List the sensor devices                           |
| GET    | `/sensor/data/`     | `sensor_router.py`    | Sensor readings in pages, or averaged per unit    |
| GET    | `/pump/`            | `pump_router.py`      | List the pumps                                    |
| GET    | `/pump/mode/`       | `pump_router.py`      | List the desired and observed pump modes          |
| PUT    | `/pump/mode/`       | `pump_router.py`      | Set the desired mode of a pump                    |
| GET    | `/pump/history/`    | `pump_router.py`      | Watering history, newest first                    |
| POST   | `/pump/history/`    | `pump_router.py`      | Record water usage (called by the device)         |
| GET    | `/pump/usage/today` | `pump_router.py`      | Litres used since local midnight                  |
| GET    | `/pump/parameters/` | `pump_router.py`      | The activation parameters the weather service set |
| GET    | `/alerts/`          | `alert_router.py`     | Alerts evaluated against the latest reading       |
| WS     | `/mc-ws/`           | `websocket_router.py` | Device publishes readings, everyone receives them |

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- SENSOR READINGS -->
### Sensor Readings

`GET /sensor/data/` lists the readings newest first, in pages:

| Parameter |                        Meaning                         |
|-----------|--------------------------------------------------------|
| `limit`   | Page size, 1 to 1000, 100 by default                   |
| `offset`  | How many of the newest readings to skip, 0 by default  |
| `since`   | Only the readings recorded at or after this moment     |
| `until`   | Only the readings recorded before this moment          |
| `bucket`  | `minute`, `hour`, `day`, `week`, `month` or `year`     |

Without `bucket` a page holds raw readings:

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

With `bucket` the readings of every unit are averaged before the page is cut, so a chart downloads the points it draws instead of every row behind them. The buckets are newest first and carry the moment their unit starts, how many readings they hold and the averages of the three values:

```json
[
  {
    "start": "2026-10-20T16:00:00",
    "moisture_level": 41.5,
    "humidity": 78.0,
    "temperature": 23.25,
    "readings": 2
  }
]
```

Weeks start on Monday and months on their first day, in both Postgres and SQLite. The endpoint says "every reading" no more: the whole table is never sent at once.

Note the name change: the device's `sensor` field is `sensor_id` in REST responses, because that is the database column name.

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- PUMP MODES -->
### Pump Modes

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

`PUT /pump/mode/` takes `{"pump": 1, "pump_mode": 2}`. Both fields are required; a missing one is a 422. The pump is created on demand if it does not exist yet. The mode is an ordinal — see the table in the [root README](../README.md#shared-contract).

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- PUMP HISTORY -->
### Pump History

`POST /pump/history/` takes `{"liters": 0.006, "pump": 1}`. `recorded_at` is optional and defaults to now. `GET /pump/history/` returns the entries newest first:

```json
[
  { "id": 12, "liters": 0.006, "recorded_at": "2026-10-20T16:02:11", "pump_id": 1 }
]
```

`GET /pump/usage/today` sums the litres recorded since local midnight and returns `{"liters": 12.5}`.

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- ALERTS -->
### Alerts

`GET /alerts/` returns `{"alerts": [{"message": "...", "severity": "..."}]}`.

`app/services/alert_service.py` evaluates the **latest** reading only:

|           Condition           |             Message              |  Severity  |
|-------------------------------|----------------------------------|------------|
| No readings at all            | "No sensor readings yet"         | `warning`  |
| Latest reading is garbled     | "Spooky sensor data detected: …" | `spooky`   |
| Humidity ≤ 20 %               | "Check humidity levels"          | `critical` |
| Moisture ≤ 30 %               | "Soil moisture is low"           | `warning`  |
| Reading older than 30 minutes | "Sensor readings are stale"      | `warning`  |

A garbled reading short-circuits everything else: the thresholds would be judging fake numbers.

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- WEBSOCKET -->
### WebSocket

`/mc-ws/` is the live channel. The ESP32 connects to it and publishes readings; the API stores each one and broadcasts it to every socket on the channel, including the app.

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

The handler in `routers/websocket_router.py` validates the payload against `SensorDataRequest`, saves it, and broadcasts it. The broadcast payload (`services/websocket_service.py`) is the stored row plus an ISO-8601 `recorded_at`; it keeps the key name `sensor`.

A malformed payload raises a Pydantic `ValidationError` that is not caught, so it closes the connection.

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- PUMP-MODE POLLING -->
### Pump-Mode Polling

`app/services/device_service.py` reconciles the modes stored in the database with the modes the device is actually running. It only runs when `DEVICE_URL` is set.

Every `DEVICE_POLL_INTERVAL_SECONDS` the poller:

1. `GET {DEVICE_URL}/mode` and reads the current mode of each pump.
2. Writes those into `pump_mode.observed_mode` and `pump_mode.last_seen_at`.
3. For any pump whose observed mode differs from the desired `pump_mode.mode`, sends `POST {DEVICE_URL}/mode` with `{"pump": 1, "mode": "DRIP"}`.
4. Records the mode the device confirmed.

The device speaks mode **names**, the database speaks **ordinals**; `app/modes.py` converts between them. Network failures are logged and swallowed, so an unreachable device never takes the API down.

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- THE WEATHER SERVICE -->
### The Weather Service

`app/services/weather_service.py`, `app/services/gemini_service.py` and `app/services/irrigation_service.py` run a background task that keeps the pumps in step with the weather. The task starts with the app, unless `WEATHER_ENABLED` is `false`.

Every `WEATHER_POLL_INTERVAL_SECONDS` the task:

1. Reads the **weather** of the next days from Open-Meteo: the current temperature and humidity, and the rain, the temperatures and the evaporation of every forecast day.
2. Reads the **climate** of the place from Open-Meteo: the reanalysis of the last `WEATHER_CLIMATE_PAST_DAYS` days, which is the seasonal normal the forecast is compared against.
3. Reads the **state of the greenhouse**: the readings the microcontroller sent over the WebSocket, the last real reading of every sensor and how the soil moisture moved, how long ago each pump watered and how much water it used today.
4. Asks **Gemini** to decide, in `app/services/gemini_service.py`. It gets the weather, the climate, the state of every zone and the parameters the pumps run with now, and it answers with json only: whether each pump may water at all, the moisture threshold it waters at, the minutes it has to wait between two activations, the mode it waters in, and a sentence saying why.
5. Checks the answer and writes the **activation parameters** of every pump into `pump_parameter`.
6. Sets the mode of the pumps that changed, which the device poller then pushes to the microcontroller.

Both outside sources come from [Open-Meteo](https://open-meteo.com), which needs no api key. The weather and the climate are asked for separately because they say different things: the forecast says what the next days will be like, the climate says what they usually are like.

The weather service needs the internet. Without it the pumps keep the parameters they have, and the logs say that the source could not be read.

The weather service owns the pump mode. It sets the mode of a pump when Gemini or the rules move it to another one, so a manual `PUT /pump/mode/` lasts until the next cycle.

#### What Gemini Decides On

The prompt holds the three kinds of data together: the forecast, the climate normal and the readings of the greenhouse.

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

The garbled readings of the halloween easter egg are left out of the numbers, because their values are made up, and the zone is marked instead, so Gemini judges the zone on the real readings only. The firmware waters by the real readings too, so the parameters stay in step with what the pumps do.

#### When Gemini Is Not There

`GEMINI_API_KEY` decides who is in charge:

- with a key, Gemini decides and its answer is used,
- without a key, the plain rules in `compute_parameters` decide: the demand is how much water the plants need compared to a usual day, higher when the forecast is hotter and drier than usual and lower when rain is coming,
- when Gemini cannot be reached, the rules take over for that cycle.

The rules are a safety net, not the brain. Either way the answer is clamped into the limits before it is stored, so neither Gemini nor one strange day can ruin the plants:

|                   Parameter                    |  Limits  |
|-------------------------------------------|----------|
| Whether the pump may water                 | yes / no |
| Moisture threshold                          | 15 – 45 % |
| Minutes between two activations             | 15 – 720  |
| Demand                                     | 0.4 – 2.5 |

Gemini decides, the code checks: the answer is clamped into the limits and the mode has to be one the device knows, so an answer that makes no sense is thrown away and the rules decide that cycle.

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

The parameters are only written when they really change, so the logs show what the weather did to the greenhouse. A source that cannot be read is logged and the old parameters stay in place.

The microcontroller runs the pump in the mode it was told to, so the mode says how much water one activation gives. The litres of each mode are mirrored from the firmware in `app/modes.py`.

The other three fields reach the device as well: the sketch reads `GET /pump/parameters/` every minute and waters by the threshold, the interval and the flag the API decided. See the [microcontroller doc](../microcontroller/README.md#watering-logic).

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- MIGRATIONS -->
### Migrations

```powershell
cd api
uv run alembic upgrade head
```

#### In CI

`.github/workflows/migrate-prod-db.yml` applies the same command to the production database on every push to `main`. The workflow first runs the test suite, then runs `alembic upgrade head` with `DB_CONN_STR` taken from the `PROD_DB_CONN_STR` repository secret. The secret must hold the prod URL in the asyncpg form, e.g. `postgresql+asyncpg://user:password@host/database`; `alembic/env.py` swaps the driver for `psycopg2` on its own. A push to `main` therefore never reaches the prod database with failing tests, and the workflow can also be started by hand from the Actions tab.

The chain has two revisions, head is `932b8d629ca2`:

|    Revision    |                                     Change                                     |
|----------------|--------------------------------------------------------------------------------|
| `843fed31fe6a` | Creates `pump`, `sensor`, `pump_history`, `pump_mode` and `sensor_data`        |
| `932b8d629ca2` | Creates `pump_parameter`, the activation parameters of the pumps (head)         |

The eleven revisions that came before `843fed31fe6a` were squashed into that one initial migration, so the old revision ids no longer exist. A database that was already migrated with the old chain cannot be upgraded any more: Alembic cannot find the revision it is stamped with. Recreate such a database, or stamp it with `uv run alembic stamp 843fed31fe6a` once its schema is known to match the models.

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- LOGGING -->
### Logging

`app/logging_config.py` configures the standard library logging once, when `app/main.py` is imported, so every module only has to do `logger = logging.getLogger(__name__)`. Everything goes to the console, in the format `LOG_FORMAT` asks for and at the level `LOG_LEVEL` sets.

The plain text format is one line per record:

```text
2026-10-22T18:36:47 INFO     app.middleware [2b1265dbcefe4f65a5a7be9b1d7868c3] GET /health from 127.0.0.1 -> 200 in 4.4 ms
```

The json format writes one object per line, with the keys `timestamp`, `level`, `logger`, `message`, `request_id` and, when a record carries a traceback, `exception`.

Every request gets an id. `app/middleware.py` puts it in the `x-request-id` header of the answer and in every record the request produces, so the logs of a request can be told apart from the logs of everything else:

```text
2026-10-22T18:36:47 INFO     app.services.pump_service [3ae970ad130045a08c39d32016f0e8fd] pump 1 was set to DRIP mode
2026-10-22T18:36:47 INFO     app.middleware [3ae970ad130045a08c39d32016f0e8fd] PUT /pump/mode/ from 127.0.0.1 -> 200 in 3.5 ms
```

The middleware logs every request with its status code and how long it took, and logs the traceback of the errors that reach it. Uvicorn's own access log is turned off, because it would say the same thing without the id and the duration.

`LOG_LEVEL=DEBUG` also turns on the SQLAlchemy echo, so every statement the engine runs is logged as well.

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- TESTS -->
### Tests

```powershell
cd api
uv sync --group dev
uv run pytest
```

`tests/conftest.py` points `DB_CONN_STR` at a throwaway SQLite file **before** importing the app, so the tests never touch the configured database. It also sets `FRONTEND_URL=*` and disables the device poll.

Fixtures:

|   Fixture    |                                         Purpose                                          |
|--------------|------------------------------------------------------------------------------------------|
| `database`   | Creates the schema once per session, disposes the engine and deletes the file afterwards |
| `clean_db`   | Empties every table and re-seeds pumps 1–3 in `FAST` mode, before and after each test    |
| `db_session` | A database session for unit tests                                                        |
| `client`     | An `httpx.AsyncClient` talking to the app in process over `ASGITransport`                |

The suite covers 103 tests:

|            File             | Tests |                                                    What it covers                                                    |
|-----------------------------|-------|----------------------------------------------------------------------------------------------------------------------|
| `test_api.py`               |  19   | Every REST endpoint, paging and bucketing the readings, the 422s on bad queries and the 404 on an unknown path        |
| `test_websocket.py`         |   3   | A real uvicorn server: a reading is stored and broadcast, the garbled flag survives, a malformed payload is rejected |
| `test_alert_service.py`     |   8   | Every alert rule, including that a garbled reading suppresses the others and that the latest reading wins            |
| `test_pump_service.py`      |   8   | Pump and mode seeding, mode updates, history ordering, today's usage                                                 |
| `test_sensor_service.py`    |   6   | Field persistence, the garbled flag, explicit timestamps, auto-created sensors, "latest" and "recent" ordering       |
| `test_modes_and_schemas.py` |   8   | The mode order matches the microcontroller's enum, schema defaults and validation errors                             |
| `test_logging.py`           |   8   | The json formatter, the request id filter, the log level, and the request and error logs of the middleware           |
| `test_weather_service.py`   |   9   | The forecast and the climate are read from the payloads of the source, and a source that fails is reported           |
| `test_irrigation_service.py`|  23   | The demand the weather brings, the limits of the parameters, the readings Gemini sees and the parameters that are written |
| `test_gemini_service.py`     |   7   | The prompt Gemini gets, the json it is asked for, and the answers it may give back                        |

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- ROADMAP -->
## Roadmap

- [x] Paginated and bucketed sensor readings
- [x] Request logging with request ids
- [x] Pump-mode polling and reconciliation
- [x] Weather and Gemini-driven pump adjustment
- [ ] Add authentication — every endpoint and the WebSocket are open; a JWT system existed and was removed
- [ ] Add rate limiting, gzip and HTTPS redirect — CORS and request logging are the only middleware
- [ ] Add custom exception handlers — unhandled exceptions use FastAPI's default 500 handler
- [ ] Send humidity as a float end-to-end — the schema declares it as an int while the device sends a float

See the [open issues](https://github.com/invalid-code/dbtc-hacktoberfest-2026-g2/issues) for a full list of proposed features (and known issues).

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- CONTRIBUTING -->
## Contributing

Contributions are what make the open source community such an amazing place to learn, inspire, and create. Any contributions you make are **greatly appreciated**.

If you have a suggestion that would make this better, please fork the repo and create a pull request. You can also simply open an issue with the tag "enhancement".
Don't forget to give the project a star! Thanks again!

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

### Top contributors:

<a href="https://github.com/invalid-code/dbtc-hacktoberfest-2026-g2/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=invalid-code/dbtc-hacktoberfest-2026-g2" alt="contrib.rocks image" />
</a>

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- LICENSE -->
## License

Distributed under the Apache License 2.0. See the [LICENSE](../LICENSE) for more information.

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- CONTACT -->
## Contact

Project Link: [https://github.com/invalid-code/dbtc-hacktoberfest-2026-g2](https://github.com/invalid-code/dbtc-hacktoberfest-2026-g2)

Questions or bug reports: [open an issue](https://github.com/invalid-code/dbtc-hacktoberfest-2026-g2/issues/new).

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- ACKNOWLEDGMENTS -->
## Acknowledgments

* [Best-README-Template](https://github.com/othneildrew/Best-README-Template)
* [FastAPI](https://fastapi.tiangolo.com)
* [SQLAlchemy](https://www.sqlalchemy.org)
* [Alembic](https://alembic.sqlalchemy.org)
* [PostgreSQL](https://www.postgresql.org)
* [Open-Meteo](https://open-meteo.com)
* [Google Gemini](https://ai.google.dev)
* [uv](https://docs.astral.sh/uv/)
* [Shields.io](https://shields.io)
* [contrib.rocks](https://contrib.rocks)

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- MARKDOWN LINKS & IMAGES -->
<!-- https://www.markdownguide.org/basic-syntax/#reference-style-links -->
[contributors-shield]: https://img.shields.io/github/contributors/invalid-code/dbtc-hacktoberfest-2026-g2.svg?style=for-the-badge
[contributors-url]: https://github.com/invalid-code/dbtc-hacktoberfest-2026-g2/graphs/contributors
[forks-shield]: https://img.shields.io/github/forks/invalid-code/dbtc-hacktoberfest-2026-g2.svg?style=for-the-badge
[forks-url]: https://github.com/invalid-code/dbtc-hacktoberfest-2026-g2/network/members
[stars-shield]: https://img.shields.io/github/stars/invalid-code/dbtc-hacktoberfest-2026-g2.svg?style=for-the-badge
[stars-url]: https://github.com/invalid-code/dbtc-hacktoberfest-2026-g2/stargazers
[issues-shield]: https://img.shields.io/github/issues/invalid-code/dbtc-hacktoberfest-2026-g2.svg?style=for-the-badge
[issues-url]: https://github.com/invalid-code/dbtc-hacktoberfest-2026-g2/issues
[license-shield]: https://img.shields.io/github/license/invalid-code/dbtc-hacktoberfest-2026-g2.svg?style=for-the-badge
[license-url]: https://github.com/invalid-code/dbtc-hacktoberfest-2026-g2/blob/main/LICENSE
[Python.org]: https://img.shields.io/badge/Python-3776AB?style=for-the-badge&logo=python&logoColor=white
[Python-url]: https://www.python.org
[FastAPI.com]: https://img.shields.io/badge/FastAPI-009688?style=for-the-badge&logo=fastapi&logoColor=white
[FastAPI-url]: https://fastapi.tiangolo.com
[PostgreSQL.org]: https://img.shields.io/badge/PostgreSQL-4169E1?style=for-the-badge&logo=postgresql&logoColor=white
[PostgreSQL-url]: https://www.postgresql.org
[SQLAlchemy.org]: https://img.shields.io/badge/SQLAlchemy-D71F00?style=for-the-badge&logo=sqlalchemy&logoColor=white
[SQLAlchemy-url]: https://www.sqlalchemy.org
[Pydantic.dev]: https://img.shields.io/badge/Pydantic-E92063?style=for-the-badge&logo=pydantic&logoColor=white
[Pydantic-url]: https://docs.pydantic.dev
[pytest.org]: https://img.shields.io/badge/pytest-0A9EDC?style=for-the-badge&logo=pytest&logoColor=white
[pytest-url]: https://docs.pytest.org
[Gemini.ai]: https://img.shields.io/badge/Google%20Gemini-8E75B2?style=for-the-badge&logo=googlegemini&logoColor=white
[Gemini-url]: https://ai.google.dev
