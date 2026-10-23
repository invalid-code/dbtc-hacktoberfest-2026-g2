# Greenhouse IoT Specification

**Version:** 0.1.0
**Status:** Implemented baseline
**Last updated:** 2026-10-23

This document describes the behavior the codebase implements. It is the
reference for changes to the firmware, API, frontend, tests, and documentation.
If the implementation and this specification disagree, the difference is a bug
in one of them and must be resolved deliberately.

Normative words such as **MUST**, **SHOULD**, and **MAY** are used as defined
in [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119).

## 1. Purpose

The system keeps a three-zone greenhouse watered automatically and lets an
operator monitor and control it from a dashboard.

It has three runnable parts:

- an ESP32 firmware that reads the sensors, drives the pumps, and talks to the
  API,
- a FastAPI service that stores readings and water usage, serves the frontend,
  and reconciles pump modes and irrigation parameters,
- a Flutter app that shows the greenhouse state and lets the operator change
  pump modes and filter the graphs.

The system also uses two optional external services: Open-Meteo for weather and
climate data, and Google Gemini for irrigation decisions. Without them the
system keeps working with its local rules.

## 2. Scope

### In scope

- Three fixed greenhouse zones, each with one soil moisture sensor, one DHT11
  temperature/humidity sensor, and one pump.
- Automatic watering based on soil moisture, with parameters supplied by the
  API.
- Live sensor readings over a WebSocket.
- Storage of readings, pump modes, watering history, and irrigation parameters.
- Alerts derived from the latest reading.
- Weather- and AI-driven adjustment of the irrigation parameters.
- A web-capable Flutter dashboard for monitoring and pump-mode control.
- Paginated and time-bucketed reading queries for graphs.

### Out of scope

- User accounts, authentication, authorization, and multi-tenant access.
- More than one greenhouse or a configurable number of zones.
- A working `SPRINKLE` mode; the mode is reserved but does nothing on the
  device.
- Direct weather-triggered watering on the device. Weather only changes the
  parameters the device uses.
- Push notifications, email, or SMS.
- Reading buffering while the device is offline.
- Data retention or pruning policies.
- Native app-store packaging and release automation.

## 3. Terminology

| Term | Meaning |
|------|---------|
| Reading | One sensor sample: moisture, humidity, temperature, and timestamp. |
| Zone | One greenhouse position, identified by a number from 1 to 3. |
| Pump | The actuator of a zone. Pump IDs are `1`, `2`, and `3`. |
| Desired mode | The mode the API stores for a pump and wants the device to run. |
| Observed mode | The mode the API last read back from the device. |
| Activation | One pump run. |
| Activation parameters | Whether a pump may water, its moisture threshold, its interval, and its mode. |
| Bucket | Readings averaged over a unit of time (minute, hour, day, week, month, or year). |
| Garbled reading | A deliberately fake reading produced by the Halloween easter egg. |

## 4. System overview

```
                    +--------------------------+
                    | ESP32 (microcontroller)  |
                    | 3x soil, 3x DHT11        |
                    | 3x pump, HTTP mode server|
                    +-----+--------------+-----+
         WebSocket        |              |  HTTP
       /mc-ws/ readings   |              |  POST /pump/history/
                          v              v
                    +--------------------------+
                    |       FastAPI (api/)     |
                    | routers -> services ->   |
                    | repositories             |
                    |        |                 |
                    |        v                 |
                    | PostgreSQL (asyncpg)     |
                    +-----+--------------+-----+
         REST / + WebSocket |              | WebSocket /mc-ws/
                          v              v
                    +--------------------------+
                    |    Flutter (frontend/)   |
                    | go_router + ChangeNotifier|
                    +--------------------------+

External services used by the API:
  Open-Meteo  -> weather forecast + climate normal
  Gemini      -> optional irrigation decisions
```

The microcontroller and the app share the `/mc-ws/` channel. The device
publishes readings, the API stores each one, and the API broadcasts it to every
connected client, including the app.

Pump control travels the other way. The app writes the desired mode through the
API. The API's device poller pushes the mode to the device's HTTP server and
records the observed mode.

Watering parameters travel from the API to the device. The API's irrigation
service computes them from weather, climate, and greenhouse state, stores them,
and the device fetches them every minute.

## 5. Functional requirements

### 5.1 Firmware (`microcontroller/`)

- **DEV-1** The firmware MUST connect to Wi-Fi and to the API WebSocket using
  values supplied by `secrets.h`: `SSID`, `PASSWORD`, `WS_SERVER_URL`,
  `WS_SERVER_PORT`, and `WS_PATH`. It MUST retry the WebSocket connection every
  5 seconds.
- **DEV-2** The firmware MUST poll the API WebSocket and HTTP server
  continuously, and MUST reconnect Wi-Fi if the connection drops.
- **DEV-3** Every 10 seconds the firmware MUST read all three zones, map each
  raw soil value from 0-2800 to 0-100 percent, constrain the result to 0-100,
  and read temperature and humidity from the zone's DHT11.
- **DEV-4** For each zone, the firmware MUST publish a WebSocket payload with
  `sensor`, `moisture_level`, `temperature`, `humidity`, and `garbled`. It MUST
  NOT send `recorded_at`; the API assigns the timestamp.
- **DEV-5** The firmware MUST fetch `GET /pump/parameters/` every 60 seconds.
  On failure it MUST keep the last parameters it received. It MUST apply
  received parameters atomically; the sensor loop must not read a partially
  updated parameter set.
- **DEV-6** A pump MUST activate only when all of the following hold:
  - the pump is `active`,
  - the real soil moisture is at or below `moisture_threshold`,
  - the pump has never activated, the interval is zero, or
    `activation_interval_minutes` has elapsed since the last activation.
- **DEV-7** Before the API has supplied parameters, a pump MUST behave as
  `active = true`, `moisture_threshold = 30`, and no interval.
- **DEV-8** An activation MUST run the pump according to its current mode and
  MUST enqueue a water-usage report with the calculated litres. A background
  task MUST POST the report to `/pump/history/` so the sensor loop is not
  blocked.
- **DEV-9** The firmware MUST expose an HTTP server on port 80 with:
  - `GET /mode`: the current mode name of every pump,
  - `POST /mode`: set a pump's mode from JSON or form arguments,
  - `GET /parameters`: the activation parameters the device is currently using.
- **DEV-10** `POST /mode` MUST reject an unknown pump with 404 and a request
  without `pump` and `mode` with 400.
- **DEV-11** The firmware MUST implement the Halloween easter egg described in
  section 8.6. Pump decisions MUST always use the real readings, even when a
  garbled reading is published.
- **DEV-12** The firmware MUST implement the pump-mode behavior and litres per
  activation defined in section 8.1.

### 5.2 API (`api/`)

- **API-1** The API MUST be a FastAPI application using async SQLAlchemy and a
  `DB_CONN_STR` URL. It MUST expose `/health` returning `{"status": "ok"}`.
- **API-2** The API MUST NOT create or alter the schema at startup. Alembic
  migrations are the only schema authority; `alembic upgrade head` MUST run
  before the service starts.
- **API-3** At startup the API MUST seed pumps `1`, `2`, and `3` if they do not
  exist, and give them a FAST mode row if they have none. It MUST start the
  device poller only when `DEVICE_URL` is non-empty, and the irrigation poller
  only when `WEATHER_ENABLED` is true. Both background tasks MUST be cancelled
  cleanly at shutdown.
- **API-4** `GET /sensor/` MUST list all known sensors.
- **API-5** `GET /sensor/data/` MUST return readings newest first, ordered by
  `recorded_at` descending and then `id` descending. It MUST support:
  - `limit` from 1 to 1000, default 100,
  - `offset` of 0 or more, default 0,
  - `since` inclusive,
  - `until` exclusive,
  - `bucket` as `minute`, `hour`, `day`, `week`, `month`, or `year`.
  Without `bucket` it MUST return raw readings. With `bucket` it MUST return
  one averaged point per unit, newest first, containing `start`,
  `moisture_level`, `humidity`, `temperature`, and `readings`. Weeks MUST start
  on Monday. Out-of-range `limit` or `offset` values MUST be rejected with 422.
- **API-6** The WebSocket endpoint `/mc-ws/` MUST accept, validate, store, and
  broadcast sensor readings. The broadcast MUST add an ISO-8601 `recorded_at`
  and MUST keep the key `sensor` (not `sensor_id`). A malformed payload MUST
  close the connection.
- **API-7** A reading for an unknown sensor MUST create the sensor row on
  demand. A reading without `recorded_at` MUST be stamped with the current local
  time. `garbled` MUST default to `false`.
- **API-8** `GET /pump/` MUST list pumps. `GET /pump/mode/` MUST list every
  pump's desired mode, observed mode, last-seen time, and pump id.
- **API-9** `PUT /pump/mode/` MUST set the desired mode of a pump from
  `{"pump": <id>, "pump_mode": <ordinal>}`. Both fields are required. The pump
  MUST be created on demand. The endpoint MUST NOT wait for the device; the
  poller reconciles the mode.
- **API-10** The device poller MUST, every `DEVICE_POLL_INTERVAL_SECONDS`:
  1. read `GET {DEVICE_URL}/mode`,
  2. store each returned mode as `observed_mode` and the current time as
     `last_seen_at`,
  3. push every desired mode that differs from the observed mode with
     `POST {DEVICE_URL}/mode`,
  4. store the mode the device confirms.
  Device and network failures MUST be logged and MUST NOT stop the poller or
  the API.
- **API-11** `GET /pump/history/` MUST return watering entries newest first.
  `POST /pump/history/` MUST record `liters` with an optional `recorded_at`
  (default now) and an optional `pump` (creating it on demand).
  `GET /pump/usage/today` MUST sum litres from local midnight up to, but not
  including, the next local midnight.
- **API-12** `GET /alerts/` MUST evaluate only the latest reading, following
  the rules and precedence in section 8.3.
- **API-13** `GET /pump/parameters/` MUST return the stored activation
  parameters of every pump, including `mode_liters`, or an empty list when no
  parameters exist.
- **API-14** The irrigation service MUST run on a timer
  (`WEATHER_POLL_INTERVAL_SECONDS`, default one hour) and:
  1. read the weather and climate from Open-Meteo,
  2. read the latest and recent real readings per sensor and today's water
     usage,
  3. ask Gemini for per-pump decisions when `GEMINI_API_KEY` is set,
  4. fall back to the local rules when Gemini is unavailable or returns an
     invalid decision,
  5. clamp all values to the limits in section 8.4,
  6. write parameters only when they changed,
  7. set the desired mode of pumps whose mode changed.
  A weather failure MUST leave the stored parameters untouched and MUST NOT
  stop the loop.
- **API-15** The API MUST provide structured logging with `LOG_LEVEL` and
  `LOG_FORMAT` (`text` or `json`). It MUST assign every request a request ID,
  return it in the `x-request-id` response header, include it in log records,
  and log method, path, client, status, and duration. Errors MUST include their
  traceback. `DEBUG` MUST also enable SQLAlchemy statement logging.
- **API-16** CORS MUST use `FRONTEND_URL`, a comma-separated allow-list.
  `*` MUST allow all origins without credentials; any other value MUST allow
  credentials. All methods and the headers `Content-Type` and `Authorization`
  MUST be allowed.
- **API-17** Responses and requests MUST use the Pydantic schemas in
  `api/app/schemas.py`. Database access MUST go through the repositories.

### 5.3 Frontend (`frontend/`)

- **UI-1** The app MUST use `go_router` with these routes:
  - `/` - dashboard,
  - `/watering-history` - watering history,
  - `/sensor-reading` - sensor readings and trends.
- **UI-2** The API base URL MUST come from the compile-time
  `API_BASE_URL` define, defaulting to `http://localhost:8000`. A trailing
  slash MUST be stripped. HTTP requests MUST time out after 10 seconds and
  non-2xx responses MUST throw.
- **UI-3** The live feed MUST derive its WebSocket URL from the API base URL by
  replacing `http` with `ws` and appending `/mc-ws/`. It MUST reconnect after 5
  seconds and MUST ignore messages that are not sensor readings.
- **UI-4** The dashboard MUST load the latest reading, pumps, pump modes,
  today's usage, alerts, and watering history, and MUST update the latest
  reading from the live feed. It MUST show a conditions card, a water-usage
  chart, a history summary, a pump card per pump returned by `GET /pump/`, and
  the alerts card.
- **UI-5** A pump-mode change MUST call `PUT /pump/mode/` and, on success,
  update the local pump state. The labels MUST be `Fast`, `Slow`, `Drip`, and
  `Sprinkle`, in ordinal order; unknown modes MUST display `Fast`.
- **UI-6** The water-usage chart MUST sum history entries into the selected
  time range. Its default range MUST be Real-time.
- **UI-7** The sensor screen MUST show the latest reading and separate
  temperature and moisture trend charts. For Real-time it MUST plot the latest
  60 individual readings. For other ranges it MUST request the API's averaged
  buckets, request one extra bucket, cache the result per range, and refresh
  cached ranges 5 seconds after live readings arrive. Temperature and moisture
  ranges MUST be independent.
- **UI-8** The history screen MUST list every watering, formatted with the
  pump, time, and litres, and MUST support newest-first and oldest-first
  sorting.
- **UI-9** Every screen MUST handle and display loading, empty, and failure
  states. The dashboard MUST keep independent failure flags per data source.
- **UI-10** Garbled readings MUST be visibly marked as haunted/untrusted, and
  spooky alerts MUST be displayed with their severity.
- **UI-11** The layout MUST adapt to narrow screens: the dashboard MUST stack
  its panels and reduce the pump grid from three columns to two or one.

### 5.4 Cross-component contracts

- **CON-1** The pump-mode ordinal mapping MUST be identical in
  `api/app/modes.py`, `microcontroller/microcontroller.ino`, and
  `frontend/lib/model/pump_info.dart`.
- **CON-2** The sensor reading field names MUST match between firmware output,
  API request schemas, API broadcast, and frontend parsing. REST responses use
  `sensor_id`; WebSocket messages use `sensor`.
- **CON-3** Pump and sensor IDs MUST be the integers `1`, `2`, and `3`.
- **CON-4** A change to a shared payload or mode mapping MUST update the API,
  firmware, frontend, tests, and documentation in the same change.

## 6. Interfaces

### 6.1 REST API

| Method | Path | Request / parameters | Response |
|--------|------|----------------------|----------|
| GET | `/health` | - | `{"status": "ok"}` |
| GET | `/sensor/` | - | `[{"id": int}]` |
| GET | `/sensor/data/` | `limit`, `offset`, `since`, `until`, `bucket` | Raw readings or averaged buckets |
| GET | `/pump/` | - | `[{"id": int}]` |
| GET | `/pump/mode/` | - | Pump mode rows |
| PUT | `/pump/mode/` | `{"pump": int, "pump_mode": int}` | Updated pump mode row |
| GET | `/pump/history/` | - | Watering entries, newest first |
| POST | `/pump/history/` | `{"liters": float, "pump": int?, "recorded_at": datetime?}` | Created entry |
| GET | `/pump/usage/today` | - | `{"liters": float}` |
| GET | `/pump/parameters/` | - | Activation parameters per pump |
| GET | `/alerts/` | - | `{"alerts": [{"message": str, "severity": str}]}` |
| WS | `/mc-ws/` | Sensor reading JSON | Stored reading broadcast |

Representative payloads:

```json
// Raw reading
{
  "id": 1,
  "moisture_level": 42,
  "humidity": 78,
  "temperature": 23.5,
  "recorded_at": "2026-10-20T16:02:11.123456",
  "sensor_id": 1,
  "garbled": false
}
```

```json
// Averaged bucket
{
  "start": "2026-10-20T16:00:00",
  "moisture_level": 41.5,
  "humidity": 78.0,
  "temperature": 23.25,
  "readings": 2
}
```

```json
// Pump mode row
{
  "id": 1,
  "mode": 2,
  "observed_mode": 2,
  "last_seen_at": "2026-10-20T16:02:11.123456",
  "pump_id": 1
}
```

```json
// Pump parameter row
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
```

List endpoints are declared with a trailing slash. The exceptions are
`/health` and `/pump/usage/today`. The WebSocket endpoint MUST be requested
exactly as `/mc-ws/`.

### 6.2 WebSocket protocol

The device publishes:

```json
{
  "sensor": 1,
  "moisture_level": 42,
  "temperature": 23.5,
  "humidity": 78,
  "garbled": false
}
```

The API broadcasts the stored form:

```json
{
  "sensor": 1,
  "moisture_level": 42,
  "temperature": 23.5,
  "humidity": 78,
  "recorded_at": "2026-10-20T16:02:11.123456",
  "garbled": false
}
```

Every connected socket receives every reading, including the socket that sent
it. A failed send drops that client.

### 6.3 Device HTTP API

| Method | Path | Request | Response |
|--------|------|---------|----------|
| GET | `/mode` | - | `{"modes": {"1": "FAST", "2": "SLOW", "3": "DRIP"}}` |
| POST | `/mode` | JSON `{"pump": 1, "mode": "DRIP"}` or form `pump`/`mode` | `{"pump": 1, "mode": "DRIP"}` |
| GET | `/parameters` | - | `{"parameters": {"1": {...}, "2": {...}, "3": {...}}}` |

The device speaks mode names. The API converts between names and ordinals.

### 6.4 External services

- **Open-Meteo forecast:** current temperature, humidity, and precipitation;
  daily maximum/minimum temperature, precipitation sum, and FAO
  evapotranspiration for three days; timezone set automatically.
- **Open-Meteo climate:** daily mean temperature, precipitation sum, and FAO
  evapotranspiration over the last 92 days by default; timezone set
  automatically.
- **Gemini:** `POST` to the Generative Language API with a system instruction
  and a JSON response schema. It receives the forecast, climate, zone states,
  and current parameters, and returns an array of per-pump decisions. The
  default model is `gemini-3.8-flash`. This integration is optional.

## 7. Data model

All tables are managed by Alembic.

| Table | Columns |
|-------|---------|
| `sensor` | `id` (PK) |
| `sensor_data` | `id` (PK), `moisture_level` int, `humidity` int, `recorded_at` datetime indexed, `temperature` float, `garbled` bool default false, `sensor_id` FK -> `sensor.id` |
| `pump` | `id` (PK) |
| `pump_mode` | `id` (PK), `mode` int (desired), `observed_mode` int nullable, `last_seen_at` datetime nullable, `pump_id` unique FK -> `pump.id` |
| `pump_history` | `id` (PK), `liters` float, `recorded_at` datetime, `pump_id` nullable FK -> `pump.id` |
| `pump_parameter` | `id` (PK), `active` bool default true, `moisture_threshold` int default 30, `activation_interval_minutes` int default 60, `mode` int default 0, `reason` string default empty, `updated_at` datetime default now, `pump_id` unique FK -> `pump.id` |

The `sensor_data.recorded_at` index supports pagination and time filtering.
`pump_mode.mode` is the desired state; `observed_mode` and `last_seen_at` are
written only by the device poller.

Datetimes are stored as naive local times. The API uses `datetime.now()` for
defaults and for "today", "stale", and "minutes since" calculations.

## 8. Behavioral rules

### 8.1 Pump modes

| Ordinal | Name | Firmware behavior | Litres per activation |
|---------|------|-------------------|-----------------------|
| 0 | `FAST` | Full power for 750 ms | 0.0060 |
| 1 | `SLOW` | PWM 120/255 for 750 ms | 0.0028 |
| 2 | `DRIP` | 150 ms on, then 2.5 s off | 0.0012 |
| 3 | `SPRINKLE` | No-op (not implemented) | 0.0 |

The firmware flow rate is 0.008 litres per second. The litre values in the API
(`api/app/modes.py`) mirror the firmware calculation.

### 8.2 Watering decision

For each zone and cycle:

1. If the API has not provided parameters, use `active = true`,
   `threshold = 30`, and `interval = 0`.
2. If `active` is false, do not water.
3. If real soil moisture is greater than the threshold, do not water.
4. If the pump has activated before, the interval is greater than zero, and the
   elapsed time is less than the interval, do not water.
5. Otherwise activate the pump in its current mode and record the used litres.

The decision uses real sensor values even when the published reading is
garbled.

### 8.3 Alerts

Only the latest reading is considered.

| Condition | Message | Severity |
|-----------|---------|----------|
| No readings | `No sensor readings yet` | `warning` |
| Latest reading is garbled | `Spooky sensor data detected: ...` | `spooky` |
| Humidity <= 20% | `Check humidity levels` | `critical` |
| Moisture <= 30% | `Soil moisture is low` | `warning` |
| Reading older than 30 minutes | `Sensor readings are stale` | `warning` |

A garbled reading short-circuits all other rules. Otherwise multiple alerts can
be returned. If no condition matches, the list is empty.

### 8.4 Irrigation parameters

The fallback rules compare the forecast with the climate normal:

```
heat          = mean_forecast_max_temperature - mean_climate_temperature
evaporation   = mean_forecast_evaporation - mean_climate_evaporation
usual_rain    = mean_climate_daily_precipitation * 3
rain          = total_forecast_precipitation - usual_rain
dry_air       = max(0, 40 - current_humidity)

demand = 1.0
       + heat * 0.05
       + evaporation * 0.15
       + min(0, rain) * 0.05
       - max(0, rain) * 0.08
       + dry_air * 0.01
demand = clamp(demand, 0.4, 2.5)

threshold = clamp(round(30 - (demand - 1.0) * 20), 15, 45)
interval = clamp(round(60 / demand), 15, 720)
mode = DRIP   when demand <= 0.8
       SLOW   when demand <= 1.2
       FAST   otherwise
```

The local fallback always sets `active` to `true`. When Gemini does not decide
for a pump, the same fallback parameters are used for that pump.

| Parameter | Limits |
|-----------|--------|
| `active` | boolean |
| `moisture_threshold` | 15-45 |
| `activation_interval_minutes` | 15-720 |
| `mode` | `FAST`, `SLOW`, or `DRIP` only |

A Gemini decision is used only when it contains integer threshold and interval
values and a valid mode name. Values are clamped to the limits; an invalid
decision falls back to the rules for that pump. The reason is trimmed to 500
characters. Parameters are written only when they differ from the stored ones,
and the pump's desired mode is updated when the parameter mode changes.

The weather service owns the pump mode: a manual mode change lasts until the
next irrigation cycle.

Garbled readings are excluded from the recent readings shown to Gemini. If the
latest reading of a zone is garbled, the zone is marked as such. The latest
real reading is still used for the zone state.

### 8.5 Time ranges and charts

| Range | Slots | API bucket |
|-------|-------|------------|
| Real-time | 60 | none |
| Minutes | 60 | `minute` |
| Hours | 24 | `hour` |
| Days | 30 | `day` |
| Weeks | 12 | `week` |
| Months | 12 | `month` |
| Years | 5 | `year` |

Non-real-time charts request `slots + 1` buckets. Real-time charts keep the
latest 60 individual readings. Buckets without data are omitted, so gaps
remain visible. Weeks start on Monday. Axis labels follow the range: time for
minutes/hours, month and day for days/weeks, month names for months, and years
for years. Chart x-axis positions are based on real time, not on bucket index.

### 8.6 Halloween easter egg

- The haunting window is from 14 days before October 31 through October 31.
  Outside the window, no reading is garbled.
- Within the window, the probability of a garbled reading ramps linearly from
  0% at 14 days before Halloween to 80% on October 31.
- A garbled reading has moisture and humidity between 101 and 999, and
  temperature between -50.0 C and 150.0 C.
- Garbled readings are published with `"garbled": true`, stored with the flag,
  and displayed as haunted/untrusted by the frontend.
- Alerts show only the spooky alert while the latest reading is garbled.
- The firmware's pump decision always uses the real reading, never the garbled
  one.

## 9. Configuration

### 9.1 API environment

| Variable | Default | Meaning |
|----------|---------|---------|
| `DB_CONN_STR` | required | Async SQLAlchemy URL, normally `postgresql+asyncpg://...` |
| `FRONTEND_URL` | `*` | Comma-separated CORS origins |
| `DEVICE_URL` | `""` | Device base URL; empty disables polling |
| `DEVICE_POLL_INTERVAL_SECONDS` | `5.0` | Pump-mode poll interval |
| `WEATHER_ENABLED` | `true` | Enable the irrigation timer |
| `WEATHER_LATITUDE` | `14.5995` | Greenhouse latitude |
| `WEATHER_LONGITUDE` | `120.9842` | Greenhouse longitude |
| `WEATHER_POLL_INTERVAL_SECONDS` | `3600.0` | Irrigation adjustment interval |
| `WEATHER_TIMEOUT_SECONDS` | `30.0` | Open-Meteo request timeout |
| `WEATHER_CLIMATE_PAST_DAYS` | `92` | Days used for the climate normal |
| `GEMINI_API_KEY` | `""` | Gemini key; empty uses the local rules |
| `GEMINI_MODEL` | `gemini-3.8-flash` | Gemini model id |
| `GEMINI_TIMEOUT_SECONDS` | `30.0` | Gemini request timeout |
| `LOG_LEVEL` | `INFO` | `DEBUG`, `INFO`, `WARNING`, `ERROR`, or `CRITICAL` |
| `LOG_FORMAT` | `text` | `text` or `json` |

### 9.2 Frontend

| Setting | Default | Meaning |
|---------|---------|---------|
| `API_BASE_URL` | `http://localhost:8000` | Compile-time API origin, no trailing slash |

Build example:

```sh
flutter build web --dart-define=API_BASE_URL=https://api.example.com
```

### 9.3 Firmware

`microcontroller/secrets.h` is git-ignored and MUST provide:

- `SSID` and `PASSWORD` for Wi-Fi,
- `API_SERVER_URL` for REST calls,
- `WS_SERVER_URL`, `WS_SERVER_PORT`, and `WS_PATH` for the WebSocket,
- `PUMP_HISTORY_PATH` for water-usage reports.

`PUMP_PARAMETERS_PATH` may be overridden; it defaults to
`/pump/parameters/`. The WebSocket path MUST end with a slash.

## 10. Non-functional requirements

- **NFR-1 (Reliability)** The API MUST remain usable when the device, the
  weather source, or Gemini is unavailable. Failures MUST be logged and
  retried on the next cycle.
- **NFR-2 (Data volume)** The API MUST NOT return the entire reading history by
  default. Reading queries MUST be paginated, and graphs MUST use averaged
  buckets.
- **NFR-3 (Portability)** Database code MUST work on PostgreSQL in production
  and SQLite in tests. Bucket truncation MUST produce the same boundaries on
  both, including Monday-start weeks.
- **NFR-4 (Security)** Secrets MUST NOT be committed. The API stores the Gemini
  key server-side. The frontend uses no secret. The production database URL is
  a deployment secret.
- **NFR-5 (Authentication)** The baseline has no authentication. API and device
  endpoints are unauthenticated; deployments MUST restrict access through
  network controls and the CORS allow-list. Authentication is a future scope.
- **NFR-6 (Observability)** Every request MUST be traceable by its request ID,
  and logs MUST be readable by humans or machines.
- **NFR-7 (Maintainability)** Backend SQL MUST stay in repositories, business
  rules in services, and HTTP handling in routers. The frontend MUST keep
  feature code under `lib/features/` and shared code under `lib/core/`.
- **NFR-8 (Testability)** The API MUST be testable against a throwaway SQLite
  database, and the frontend MUST be testable with fake API and feed
  implementations and no real network.
- **NFR-9 (Compatibility)** Python is `>=3.14`, the Flutter SDK is `^3.12.2`,
  and the ESP32 sketch uses the Arduino framework with `WebSocketsClient`,
  `WebServer`, `ArduinoJson`, `HTTPClient`, and `DHT`.

## 11. Constraints and assumptions

- There is exactly one greenhouse with three fixed zones and three pumps.
- The device does not keep or send timestamps; the API stamps readings when
  they arrive. Network delay therefore shifts a reading's time.
- The API, device, and database use local wall-clock time; there is no explicit
  timezone setting. "Today" and the 30-minute staleness check use the API
  host's local time.
- The device HTTP server is reachable directly from the API over the network.
  There is no relay, NAT traversal, or authentication.
- The irrigation timer needs internet access for Open-Meteo. Gemini is optional.
- A `SPRINKLE` mode exists in the shared enum but has no firmware behavior; the
  API's irrigation logic never selects it.
- Readings are not buffered on the device when Wi-Fi or the WebSocket is down.
  Water-usage reports are queued in RAM and can be dropped if the queue is
  full.
- The schema must be migrated before the API starts; the app does not create
  tables.
- The frontend is deployed as a web build; the other Flutter platform scaffolds
  are present but not part of the deployment contract.

## 12. Acceptance criteria

The baseline is accepted when all of the following hold.

### 12.1 Automated tests

```sh
cd api
uv sync --group dev
uv run pytest
```

```sh
cd frontend
flutter test
```

The backend suite covers every endpoint, pagination and bucketing, WebSocket
storage and broadcast, alerts, pump seeding and modes, logging, weather,
irrigation limits, Gemini parsing, and end-to-end dashboard workflows. The
frontend suite covers JSON parsing, chart grouping and ranges, models, the live
feed, view models, the three screens, and cross-screen regressions.

### 12.2 End-to-end behavior

- A device reading over `/mc-ws/` is stored and appears on a connected
  frontend without a refresh.
- The dashboard shows the latest reading, today's usage, alerts, watering
  summary, and the three pump modes.
- Changing a pump mode in the app updates the API, and the device poller pushes
  it to the device when `DEVICE_URL` is configured.
- A pump activation on the device posts litres to `/pump/history/`, and the
  amount appears in the history and today's total.
- The sensor screen switches between Real-time and averaged ranges, and the
  graphs refresh as live readings arrive.
- A garbled reading is flagged, produces only the spooky alert, and does not
  cause the firmware to make a watering decision from fake values.
- When Gemini is not configured or fails, the local rules still produce
  parameters within the limits.
- When the weather source fails, the previously stored parameters remain.
- A stale or missing device does not stop the API or the frontend.

### 12.3 Shared contract checks

- The three mode lists agree on ordinals and names.
- The firmware payload, API schema, API broadcast, and frontend parser agree on
  field names and types.
- Pump and sensor IDs remain `1`, `2`, and `3`.

## 13. Traceability

| Area | Source of truth |
|------|-----------------|
| Firmware behavior | `microcontroller/microcontroller.ino` |
| Device HTTP API | `microcontroller/microcontroller.ino` |
| REST and WebSocket contracts | `api/app/routers/`, `api/app/schemas.py` |
| Pump-mode contract | `api/app/modes.py`, firmware, `frontend/lib/model/pump_info.dart` |
| Persistence | `api/app/models.py`, `api/alembic/` |
| Business rules | `api/app/services/` |
| Query and pagination rules | `api/app/repositories/` |
| API configuration | `api/app/config.py` |
| Frontend behavior | `frontend/lib/` |
| Frontend tests | `frontend/test/` |
| API tests | `api/tests/` |
| Deployment | `.github/workflows/migrate-prod-db.yml`, `README.md` |
| Change history | `CHANGELOG.md` |
