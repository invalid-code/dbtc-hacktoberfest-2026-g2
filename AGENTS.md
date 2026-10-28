# AGENTS.md

Rules and instructions for AI agents working on this repository.

## Project structure

- `microcontroller/` — ESP32 Arduino sketch (`microcontroller.ino`, `secrets.h`)
- `api/` — FastAPI service (`app/`, `tests/`, `alembic/`)
- `frontend/` — Flutter app (`lib/`, `test/`)

## Shared contracts

- Pump mode ordinals must match across `api/app/modes.py`, `microcontroller/microcontroller.ino`, and `frontend/lib/model/pump_info.dart`.
- Sensor payload keys (`sensor`, `moisture_level`, `temperature`, `humidity`, `garbled`) must stay consistent.
- Pump and sensor IDs are `1`, `2`, `3`.

## Changes

- Firmware, API, frontend, tests, and documentation must be updated together when a shared contract changes.
- `secrets.h` is git-ignored; never commit it.
- Schema changes require Alembic migrations (`api/alembic/`).

## Testing

- API: `cd api && uv sync --group dev && uv run pytest`
- Frontend: `cd frontend && flutter test`
- Do not break existing tests.

## Behavior

- The firmware must not make HTTP requests; it uses the WebSocket `/mc-ws/`.
- The API broadcasts readings to all connected sockets and pushes `modes`/`parameters` to the device.
- Mode changes from the frontend go through `PUT /pump/mode/`, which broadcasts a `mode` message; the device acknowledges with `mode_applied`. Pump activation should follow the irrigation parameters, not the mode change itself.
