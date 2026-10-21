# Greenhouse IoT

The project has three connected parts:

- `microcontroller/` reads the ESP32 sensors and sends JSON readings to the API
  over `/mc-ws/`.
- `api/` stores sensor readings and pump history in PostgreSQL and exposes the
  REST API used by the app.
- `frontend/` is a Flutter app that reads the REST API and sends pump-mode
  changes back to the API.

## Deploying the API

Set these environment variables in the API deployment:

```text
DB_CONN_STR=postgresql+asyncpg://user:password@host/database
FRONTEND_URL=https://your-frontend.example.com
```

`FRONTEND_URL` may be a comma-separated list for multiple deployed origins. Set
`GEMINI_API_KEY` to a Google AI Studio key to enable the AI endpoints, and
optionally `GEMINI_MODEL` to pick a different model (default
`gemini-3.8-flash`). Run
the Alembic migrations before starting the service:

```powershell
cd api
uv run alembic upgrade head
uv run uvicorn app.main:app --host 0.0.0.0 --port 8000
```

The API health check is `GET /health`. Sensor devices send their readings to
the WebSocket endpoint `/mc-ws/` with this payload:

```json
{
  "sensor": 1,
  "moisture_level": 42,
  "humidity": 78,
  "temperature": 23.5,
  "garbled": false
}
```

The API stores the readings and broadcasts them to the connected clients, so
the frontend receives the same `moisture_level`, `humidity`, `temperature` and
`recorded_at` fields over the WebSocket.

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

## AI endpoints

When `GEMINI_API_KEY` is set, the API answers with Gemini. Both endpoints read
the latest sensor reading, the recent readings, the pump history and the
active alerts, and use that state as context.

- `GET /gemini/insight/` returns a short insight and the next action to take.
- `POST /gemini/ask/` takes `{"question": "..."}` and answers it about the
  greenhouse.

```json
{
  "insight": "Soil moisture is trending down over the last readings, so the next watering is due soon.",
  "model": "gemini-3.8-flash"
}
```

## Deploying the frontend

Build the Flutter app with the deployed API origin, without a trailing slash:

```powershell
cd frontend
flutter build web --dart-define=API_BASE_URL=https://your-api.example.com
```

For local development, the client defaults to `http://localhost:8000`.

## Connecting the ESP32

Create `microcontroller/secrets.h` from the device's local configuration and
set `SERVER_URL`, `SERVER_PORT`, and `WS_PATH` to the API deployment. For a
TLS-enabled deployment, configure the ESP32 WebSocket library for `wss://` and
the API's secure WebSocket port. Do not commit `secrets.h`.
