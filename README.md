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

`FRONTEND_URL` may be a comma-separated list for multiple deployed origins. Run
the Alembic migrations before starting the service:

```powershell
cd api
uv run alembic upgrade head
uv run uvicorn app.main:app --host 0.0.0.0 --port 8000
```

The API health check is `GET /health`. Sensor devices can use either the
WebSocket endpoint `/mc-ws/` or `POST /sensor-data/` with this payload:

```json
{
  "sensor": 1,
  "moisture_level": 42,
  "water_level": 78
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
