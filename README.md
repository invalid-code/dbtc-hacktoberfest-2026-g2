# Greenhouse IoT

A three-part IoT project that keeps a greenhouse watered and lets you watch it
from a dashboard.

- `microcontroller/` — an ESP32 sketch. It reads soil moisture and DHT11
  temperature/humidity sensors, waters the plants on its own, and publishes
  readings to the API over a WebSocket.
- `api/` — a FastAPI service. It stores sensor readings and pump history in
  PostgreSQL, serves the REST API used by the app, and relays live readings to
  connected clients.
- `frontend/` — a Flutter app. It shows the dashboard, the watering history
  and the sensor trends, and sends pump-mode changes back to the API.

Component-level documentation:

| Component          |                           Doc                          |
|--------------------|--------------------------------------------------------|
| `api/`             | [api/README.md](api/README.md)                         |
| `frontend/`        | [frontend/README.md](frontend/README.md)               |
| `microcontroller/` | [microcontroller/README.md](microcontroller/README.md) |

## Architecture

```
                    ┌──────────────────────────┐
                    │ ESP32 (microcontroller)  │
                    │ DHT11 x3, soil sensors x3│
                    │pumps x3, HTTP mode server│
                    └────────┬───────────┬─────┘
              WebSocket      │           │  HTTP
        /mc-ws/ (readings)   │           │  POST /pump/history/
                    ┌────────▼───────────▼───────┐
                    │       FastAPI (api/)       │
                    │ routers → services → repos │
                    │        ↕ SQLAlchemy        │
                    │    PostgreSQL (asyncpg)    │
                    └────────▲───────────▲───────┘
                    REST /   │           │  WebSocket /mc-ws/
                    ┌────────┴───────────┴───────┐
                    │    Flutter (frontend/)     │
                    │ go_router + ChangeNotifier │
                    └────────────────────────────┘
```

The microcontroller and the app share one WebSocket channel. The device
publishes readings to `/mc-ws/`, the API stores each one and broadcasts it to
every connected socket, and the app renders it live.

Pump modes travel the other way: the app writes the desired mode to the API,
the API stores it, and the API's poller pushes it to the device over HTTP.

### The three data flows

**1. Sensor readings — device → API → app**

```
ESP32 (every 10 s)  ──WS /mc-ws/──▶  API
                                     ├─▶ INSERT sensor_data
                                     └─▶ broadcast ──▶ app updates the dashboard live
```

**2. Pump modes — app → API → device**

```
app dropdown         ──PUT /pump/mode/──▶  API (stores desired mode)
API poller           ──GET/POST /mode──▶  ESP32 (switches the pump)
                                          API records the observed mode
```

**3. Water usage — device → API → app**

```
ESP32 (after a pump runs)  ──POST /pump/history/──▶  API
app                                                 ──GET /pump/history/──▶ API
```

**4. Weather — outside → AI → pumps**

```
Open-Meteo (hourly)  ──▶  API weather service
                            ├─▶ reads the forecast and the climate
                            └─▶ Gemini reads them with the state of the greenhouse
                                 ├─▶ decides when each pump may water
                                 ├─▶ the mode goes to the device, the poller pushes it
                                 └─▶ the ESP32 reads the parameters and waters by them
```

### Shared contract

These shapes are agreed between all three parts. Changing one means changing
the others.

**Sensor reading** (device → API over WebSocket, and API → app over WebSocket):

```json
{
  "sensor": 1,
  "moisture_level": 42,
  "temperature": 23.5,
  "humidity": 78,
  "garbled": false
}
```

`recorded_at` is optional on input; the API stamps it with `datetime.now()`
when the device omits it and always returns it as an ISO-8601 string. In REST
responses the device's `sensor` field is named `sensor_id` because that is the
column name; the WebSocket broadcast keeps the name `sensor`.

**Pump mode ordinals.** The mode is stored as an integer everywhere, and the
integers are the ordinals of the Arduino `OperatingMode` enum:

| Ordinal | Mode       | Behaviour             | Litres per run |
|---------|------------|-----------------------|----------------|
|    0    |   `FAST`   | full power for 750 ms |     0.0060     |
|    1    |   `SLOW`   | 47 % PWM for 750 ms   |     0.0028     |
|    2    |   `DRIP`   | 150 ms on, 2.5 s off  |     0.0012     |
|    3    | `SPRINKLE` | not implemented       |       0.0      |

`api/app/modes.py`, `microcontroller/microcontroller.ino` and
`frontend/lib/model/pump_info.dart` each hold the same ordered list. The
device's own HTTP API speaks mode *names* (`"DRIP"`); the conversion happens
in `api/app/services/device_service.py`.

**Pump history.** The device posts `{"pump": 1, "liters": 0.0060}`. The API
returns `{"id", "liters", "recorded_at", "pump_id"}`.

**Alert.** `{"message": "...", "severity": "critical|warning|spooky"}`.

**Pump IDs** are `1`, `2`, `3` in the database, on the device, and in the app.

### Trailing slashes

Every list endpoint is declared with a trailing slash (`/sensor/data/`,
`/pump/`, `/pump/mode/`, `/pump/history/`, `/alerts/`). FastAPI redirects a
missing slash with a 307, but the WebSocket endpoint is not redirected, so
`/mc-ws/` must be requested exactly as written. The only slash-less endpoints
are `/health` and `/pump/usage/today`.

## Project layout

```
.
├── api/                  FastAPI service
│   ├── app/
│   │   ├── main.py           app factory, CORS, lifespan, router wiring
│   │   ├── config.py         pydantic-settings, environment variables
│   │   ├── database.py       async engine, session factory, get_db dependency
│   │   ├── models.py         SQLAlchemy models
│   │   ├── schemas.py        Pydantic request/response models
│   │   ├── modes.py          pump mode enum and ordinal helpers
│   │   ├── routers/          HTTP + WebSocket route handlers
│   │   ├── services/         business logic
│   │   └── repositories/     all SQL lives here
│   ├── alembic/          database migrations
│   └── tests/            pytest suite, runs on a throwaway SQLite database
├── frontend/             Flutter app
│   ├── lib/
│   │   ├── main.dart         entry point, theme, dependency injection seams
│   │   ├── router/           go_router setup and route constants
│   │   ├── core/network/     HTTP client and WebSocket feed
│   │   ├── core/widgets/     shared panels, sidebar, charts, formatters
│   │   ├── model/            shared models (alert, pump)
│   │   └── features/         feature-first screens, view models and widgets
│   └── test/             flutter_test suite
└── microcontroller/      Arduino sketch for the ESP32
    ├── microcontroller.ino
    └── secrets.h         local credentials, git-ignored, never commit it
```

## Running it locally

### 1. The API

```powershell
cd api
uv sync --group dev
```

Create `api/.env`:

```text
DB_CONN_STR=postgresql+asyncpg://postgres:password@localhost:5432/greenhouse
FRONTEND_URL=http://localhost:8080
WEATHER_LATITUDE=14.5995
WEATHER_LONGITUDE=120.9842
```

`FRONTEND_URL` is the CORS allow-list. It accepts a comma-separated list of
origins, and `*` allows everything. Set `DEVICE_URL` to the ESP32's IP address
to enable pump-mode polling (see the [microcontroller
doc](microcontroller/README.md#api-device-polling)). `WEATHER_LATITUDE` and
`WEATHER_LONGITUDE` say where the greenhouse stands, the weather service asks
for the forecast and the climate of that place and adjusts the pumps with it
(see the [weather doc](api/README.md#the-weather-service)).

The API logs every request to the console. `LOG_LEVEL` and `LOG_FORMAT` in
`api/.env` say how much is logged and whether it is plain text or json, see
the [logging doc](api/README.md#logging).

Then run the migrations and start the service:

```powershell
cd api
uv sync --group dev
uv run alembic upgrade head
uv run uvicorn app.main:app --host 0.0.0.0 --port 8000
```

The API health check is `GET /health`. Interactive docs are at `/docs`.

### 2. The frontend

```powershell
cd frontend
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000
```

`API_BASE_URL` defaults to `http://localhost:8000`, so the flag is only needed
when pointing at a different host. The app derives its WebSocket URL from the
same value by rewriting `http` to `ws`.

### 3. The microcontroller

Copy the device's local configuration into `microcontroller/secrets.h`:

```cpp
#define SSID "your-wifi"
#define PASSWORD "your-wifi-password"
#define WS_SERVER_URL "your-api-host"
#define WS_SERVER_PORT 443
#define WS_PATH "/mc-ws/"
#define API_SERVER_URL "https://your-api-host"
#define PUMP_HISTORY_PATH "/pump/history/"
```

`secrets.h` is git-ignored. Do not commit it. For a TLS deployment the
WebSocket library needs to be configured for `wss://`.

## Deploying the API

Set these environment variables in the API deployment:

```text
DB_CONN_STR=postgresql+asyncpg://user:password@host/database
FRONTEND_URL=https://your-frontend.example.com
```

Run the Alembic migrations before starting the service:

```powershell
cd api
uv run alembic upgrade head
uv run uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Set `WEATHER_LATITUDE` and `WEATHER_LONGITUDE` to the place of the greenhouse
so the weather service can adjust the pumps, and set `WEATHER_ENABLED=false`
to turn that service off. Set `GEMINI_API_KEY` to a Google AI Studio key to
let Gemini decide how the pumps behave; without it the rules decide.

### Automated migrations on `main`

`.github/workflows/migrate-prod-db.yml` runs the Alembic migrations against
the production database on every push to `main`: the test suite runs first,
then `alembic upgrade head` is applied to the prod database. The workflow can
also be started by hand from the Actions tab.

The prod connection string is read from a repository secret, so it never
enters the repository. Add it once under
**Settings → Secrets and variables → Actions**:

| Secret             | Value                                                                                  |
|--------------------|----------------------------------------------------------------------------------------|
| `PROD_DB_CONN_STR` | The prod database URL, in the same form as `DB_CONN_STR`, e.g. `postgresql+asyncpg://user:password@host/database` |

The secret can also live in a GitHub environment named `production`; the
workflow uses that environment, so environment-level protections (required
reviewers) apply to the migration.

## Deploying the frontend

Build the Flutter app with the deployed API origin, without a trailing slash:

```powershell
cd frontend
flutter build web --dart-define=API_BASE_URL=https://your-api.example.com
```

## Halloween easter egg

The microcontroller starts to play tricks as Halloween approaches. In the two
weeks before the 31st of October it occasionally replaces a reading with
garbled values, and the chance grows every day until it reaches 80% on
Halloween night itself. Outside that window the sensors always report the real
values.

Garbled readings are flagged with `"garbled": true` so they can be told apart
from the real ones. The API stores the flag, raises a spooky alert instead of
the usual threshold alerts while a garbled reading is the latest one, and the
app marks the readings as haunted. The microcontroller keeps using the real
readings for the pump logic, so the greenhouse keeps watering itself.

## The automatic watering

The API runs a background service that keeps the pumps in step with the
weather. It reads the forecast of the next days and the climate of the place
from [Open-Meteo](https://open-meteo.com), adds the state of the greenhouse,
and asks **Gemini** what every pump should do: whether it may water at all,
the moisture threshold it waters at, the minutes it waits between two
activations, and the mode it waters in. The mode is what the microcontroller
gets, so it is how the amount of water is decided.

Without a `GEMINI_API_KEY` the plain rules decide instead, and the answer is
always clamped into its limits before it is stored.

`GET /pump/parameters/` shows what was decided and why. See the
[weather doc](api/README.md#the-weather-service) for the details.

## Running the tests

The API tests run against a throwaway SQLite database, they never touch the
configured one:

```powershell
cd api
uv sync --group dev
uv run pytest
```

The frontend tests need the Flutter SDK:

```powershell
cd frontend
flutter test
```

## Current limitations

- **No authentication.** Every REST endpoint and the WebSocket are open. A JWT
  login system existed once and was removed; the schema has no user tables at
  all now. Nothing replaced it. Do not expose the API to the public internet
  without adding auth first.
- **`GET /sensor/data/` returns the whole table**, with no pagination, filter
  or ordering. It will grow without bound.
- **The pump activation parameters are not shown.** Gemini writes them, the
  API exposes them at `GET /pump/parameters/` and the ESP32 waters by them,
  but the app has no screen for them yet.
- **The pump list in the dashboard is hard-coded** to three cards in
  `frontend/lib/features/home/presentation/home_view.dart` rather than driven
  by the pumps the API returns.
- **The `observed_mode` and `last_seen_at` fields** the API exposes for pump
  modes are not read by the frontend.
