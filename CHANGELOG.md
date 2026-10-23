# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

Each version below corresponds to a single commit on `main`, in reverse
chronological order, identified by its short SHA. Merge commits are included
for completeness.

## [Unreleased]

### Added

- `SPEC.md`, the normative description of the system's components, contracts,
  behavior, configuration, and acceptance criteria.
- Microcontroller registration when a socket connects to `/mc-ws/`, which
  provisions sensors 1-3 and pumps 1-3 if they are missing.
- The API pushes pump modes and activation parameters to the microcontroller
  over `/mc-ws/`, and the device sends water usage over the same socket.
- Mode changes from the app run the pump immediately, and the device confirms
  the applied mode so the API records the observed mode.

### Changed

- The dashboard now renders one pump card per pump returned by `GET /pump/`
  instead of hard-coding three cards.
- The microcontroller uses only the WebSocket: it no longer runs an HTTP server
  or makes HTTP requests, and the API no longer polls it.
- A watering now runs until the soil reaches its moisture threshold, with a
  30-second safety timeout, and reports the litres actually delivered.
- `mode_liters` is now `mode_liters_per_second` and describes the average flow
  of a mode instead of the amount of one fixed-length run.

### Removed

- The local-only running status and start/stop button from the pump cards.
- The device HTTP poller and the `DEVICE_URL` and
  `DEVICE_POLL_INTERVAL_SECONDS` settings.

## [42ec0ba] - 2026-10-23 - test: added regression tests to the backend and frontend

### Added

- Backend regression tests for the dashboard workflow, paginated readings,
  bucket averaging and boundaries, garbled alerts, and cross-day water usage.
- Frontend regression tests for the dashboard flow and chart range bucket
  requests.

### Changed

- Documented the regression suites in the API and frontend READMEs.

## [f1d565f] - 2026-10-23 - feat: updated how to view continuous data graphs in the frontend, updated README docs to follow a format, and paginated sensor data endpoint

### Added

- Pagination for `GET /sensor/data/` with `limit`, `offset`, `since`, and
  `until`, plus optional time-bucket aggregation.
- `BucketUnit` and `SensorBucketResponse` schemas and sensor bucket service.
- Database index on `sensor_data.recorded_at`.
- Scrollable continuous chart widget and `SensorBucket` frontend model.

### Changed

- Sensor history now fetches paged and bucketed data while scrolling.
- Updated chart series, time-range models, and the frontend API client.
- Restructured the root, API, frontend, and microcontroller READMEs.

## [b0d4e0f] - 2026-10-22 - feat: made the spacing in the x-axis of the graphs time-based

### Changed

- Chart x-axis spacing and labels now reflect real time intervals instead of
  fixed per-bucket spacing.
- Updated the chart painter, chart series, tests, and frontend docs.

## [0d0140c] - 2026-10-22 - feat: added real time filtering to graphs in the frontend

### Added

- Real-time time-range filtering for sensor and usage graphs.

### Changed

- Moved time-range state into the chart series and sensor/home view models.
- Updated the router, graph widgets, tests, and frontend docs.

## [55ba1ac] - 2026-10-22 - feat: added logging, frontend graph filters, and backend api ai integration

### Added

- Structured logging with plain-text and JSON formatters, request IDs, and
  request logging middleware.
- Pump parameters model, migration, repository, and endpoint.
- Weather service using Open-Meteo forecasts and climate data, plus an
  irrigation service that combines weather, climate, and Gemini decisions.
- Gemini-driven pump activation, threshold, interval, and mode selection with
  a rule-based fallback.
- Frontend chart series and time-range models with a time-range filter widget.
- Tests for logging, weather, irrigation, Gemini, chart series, and view
  models.

### Changed

- Expanded API configuration, models, schemas, routers, and services for
  AI-driven irrigation.
- Updated home and sensor views, view models, and chart widgets for filtering.
- Expanded API, frontend, and microcontroller documentation.

## [8a78ea2] - 2026-10-22 - docs: updated docs microcontroller sensors and api pydantic schemas

### Added

- GitHub Actions workflow that runs the API tests and applies database
  migrations to production on pushes to `main`.

### Changed

- Documented the microcontroller sensors and API Pydantic schemas.
- Clarified the `garbled` flag and corrected firmware pin documentation.

## [5199e57] - 2026-10-22 - chore: reset the database migrations

### Changed

- Reset the Alembic migration history to a clean baseline.

## [c7d61e0] - 2026-10-21 - docs: updated docs formatting

### Changed

- Reformatted the root, API, frontend, and microcontroller READMEs.

## [8e25f02] - 2026-10-21 - docs: Add Apache License 2.0

### Added

- Apache License 2.0.

## [1d10d78] - 2026-10-21 - docs: added docs

### Added

- Full project documentation covering architecture, data flows, setup, usage,
  deployment, tests, and the roadmap.
- Detailed API, frontend, and microcontroller READMEs.
- Module and function docstrings across the backend, frontend, and firmware.

### Changed

- Documented configuration options, endpoints, and component behavior.

## [e4541e4] - 2026-10-21 - test: added tests

### Added

- Backend pytest suites for alerts, API routes, modes and schemas, pump
  service, sensor service, and WebSockets.
- Frontend tests for models, the sensor feed, view models, and widgets, with
  shared fake implementations.

### Changed

- Adjusted the WebSocket feed and home view for testability.
- Updated firmware behavior and pytest configuration.

## [0946bb4] - 2026-10-21 - feat: added easter egg

### Added

- Halloween firmware behavior that sends garbled readings with a probability
  that grows to 80% on Halloween night.
- `garbled` flag persisted and exposed by the API.
- Spooky alert rule and haunted frontend states for garbled readings.

### Changed

- Pump decisions continue to use the real readings during the easter egg.
- Documented the easter egg in the project READMEs.

## [39690d4] - 2026-10-20 - fix: fixed endpoints in frontend

### Added

- Gemini insight and question endpoints backed by a new Gemini service.
- Tests for the Gemini service and the frontend API client.

### Fixed

- Corrected the frontend API endpoint paths and WebSocket handling.

### Changed

- Updated the pump card, home view model, sensor model, router, and pump info
  to use the corrected endpoints.

## [f05fd26] - 2026-10-20 - feat: the microcontroller now sends updates of water usage to the api backend

### Added

- Firmware calculates and posts pump water usage updates to the API.

## [8e401f4] - 2026-10-20 - refactor: polling pump mode instead of sending it through the websocket connection

### Added

- Pump-mode polling from the API to the device.
- Device service, `modes` module, and pump mode observed-state migration.

### Changed

- Removed pump-mode pushes from the WebSocket service.
- Updated the pump repository, service, router, schemas, firmware, and
  frontend pump card to use polling.

## [f228de3] - 2026-10-20 - refactor: made codebase follow conventions

### Changed

- Split the backend into routers, services, and repositories.
- Split frontend screens into view models and widgets and aligned naming
  conventions.
- Replaced `water_level` with `humidity` through a migration.
- Restructured the firmware to follow the new conventions.

## [70082fe] - 2026-10-20 - refactor: moved frontend code to different files for clarity

### Added

- Feature folders for home, history, and sensors, plus core widgets, models,
  routing, and a sensor WebSocket client.
- Temperature column migration for sensor data.

### Changed

- Moved frontend code out of `main.dart` into focused files and widgets.
- Updated firmware and backend for the new sensor temperature field.

## [52be338] - 2026-10-19 - Merge pull request #2 from JP3756/feat/connect-iot-data-flow

### Changed

- Merged the IoT sensor and frontend data flow branch.

## [2768399] - 2026-10-19 - feat: connect IoT sensor and frontend data flow

### Added

- Multi-client WebSocket broadcasting, a health endpoint, and direct sensor
  data posting.
- Automatic sensor and pump provisioning and comma-separated CORS origins.

### Changed

- Aligned the frontend API client and firmware with the sensor data flow.
- Documented the IoT data flow in the README.

## [3b59cac] - 2026-10-19 - refactor: used built-in navigation instead of previous implementation

### Changed

- Replaced the custom navigation implementation with `go_router`.
- Reworked the API client and main app wiring.
- Added the `go_router` dependency.

## [36a0c43] - 2026-10-18 - feat: connect water usage history, alerts, and history summary to backend

### Added

- API endpoints for alerts and today's water usage.
- Frontend API client methods for water usage history, alerts, and the
  history summary.

### Changed

- Connected the dashboard and history screens to the new backend data.
- Removed the print helper files.

## [5398d71] - 2026-10-18 - feat: wired watering history data to frontend

### Added

- Pump history table and sensor `recorded_at` migrations.
- Pump history GET and POST endpoints.
- Frontend watering history view and API client methods.
- Web development configuration for the frontend.

### Changed

- Updated sensor and pump models, schemas, and the main frontend layout.

## [2326b0b] - 2026-10-17 - chore: removed vercel.json

### Changed

- Minor firmware update.

### Removed

- Root `vercel.json` deployment configuration.

## [aaa9f78] - 2026-10-17 - Merge pull request #1 from JP3756/main

### Changed

- Merged the Flutter greenhouse frontend and backend connection branch.

## [2407255] - 2026-10-17 - Allow Vercel frontend API access

### Fixed

- Allowed the deployed Vercel frontend origin to access the API.

## [cbd04df] - 2026-10-17 - Fix Vercel Flutter build configuration

### Fixed

- Moved the Vercel configuration to the repository root.
- Corrected the Flutter build configuration for Vercel.

## [b5b51da] - 2026-10-17 - Connect Flutter frontend to backend and Vercel

### Added

- Flutter API client and a dashboard connected to the backend.
- Vercel deployment configuration for the frontend.

### Changed

- Enabled CORS for the frontend and updated frontend dependencies and tests.

## [59dea83] - 2026-10-16 - feat: added frontend(flutter) project and adhere to backend plan

### Added

- Sensor and pump models, tables, and migrations.
- Sensor foreign key on sensor data and per-pump pump modes.
- Sensor and pump read endpoints and pump-mode updates.

### Changed

- Substantially expanded the firmware for the new data model.

## [1ad64f0] - 2026-10-16 - feat: added frontend(flutter) project and adhere to backend plan

### Added

- Flutter project scaffold for Android, iOS, web, Linux, macOS, and Windows.
- Initial Flutter application and Alembic migration setup.

### Changed

- Restructured sensor data fields and updated the microcontroller.
- Added initial migrations for the new backend data model.

### Removed

- Login and registration system, JWT security and dependency modules, and the
  committed `.env` file.

## [3c5c6e2] - 2026-10-11 - Add TODO list to README

### Added

- Project TODO list in the README.

## [4cddfa4] - 2026-10-11 - feat: added backend

### Added

- Initial FastAPI backend with async SQLAlchemy, PostgreSQL configuration,
  models, schemas, JWT authentication, sensor data endpoints, and a WebSocket
  endpoint.
- Initial ESP32 firmware.
- `uv` project configuration, environment files, and backend README.
