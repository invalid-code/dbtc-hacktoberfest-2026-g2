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
  <a href="https://github.com/invalid-code/dbtc-hacktoberfest-2026-g2">
    <img src="https://img.shields.io/badge/Greenhouse-IoT-2d7600?style=for-the-badge" alt="Greenhouse IoT" height="40">
  </a>

  <h3 align="center">Greenhouse IoT</h3>

  <p align="center">
    A three-part IoT project that keeps a greenhouse watered and lets you watch it from a dashboard.
    <br />
    <a href="#architecture"><strong>Explore the docs »</strong></a>
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
        <li><a href="#architecture">Architecture</a></li>
        <li><a href="#the-data-flows">The Data Flows</a></li>
        <li><a href="#shared-contract">Shared Contract</a></li>
        <li><a href="#project-layout">Project Layout</a></li>
        <li><a href="#built-with">Built With</a></li>
      </ul>
    </li>
    <li>
      <a href="#getting-started">Getting Started</a>
      <ul>
        <li><a href="#prerequisites">Prerequisites</a></li>
        <li><a href="#installation">Installation</a></li>
      </ul>
    </li>
    <li>
      <a href="#usage">Usage</a>
      <ul>
        <li><a href="#the-automatic-watering">The Automatic Watering</a></li>
        <li><a href="#halloween-easter-egg">Halloween Easter Egg</a></li>
        <li><a href="#deployment">Deployment</a></li>
        <li><a href="#running-the-tests">Running the Tests</a></li>
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

A three-part IoT project that keeps a greenhouse watered and lets you watch it from a dashboard.

- `microcontroller/` — an ESP32 sketch. It reads soil moisture and DHT11 temperature/humidity sensors, waters the plants on its own, and publishes readings to the API over a WebSocket.
- `api/` — a FastAPI service. It stores sensor readings and pump history in PostgreSQL, serves the REST API used by the app, and relays live readings to connected clients.
- `frontend/` — a Flutter app. It shows the dashboard, the watering history and the sensor trends, and sends pump-mode changes back to the API.

Component-level documentation:

| Component          |                           Doc                          |
|--------------------|--------------------------------------------------------|
| `api/`             | [api/README.md](api/README.md)                         |
| `frontend/`        | [frontend/README.md](frontend/README.md)               |
| `microcontroller/` | [microcontroller/README.md](microcontroller/README.md) |

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- ARCHITECTURE -->
### Architecture

```
                    ┌──────────────────────────┐
                    │ ESP32 (microcontroller)  │
                    │ DHT11 x3, soil sensors x3│
                    │       pumps x3           │
                    └────────────┬─────────────┘
                                 │  WebSocket /mc-ws/
                                 │  readings and usage up,
                                 │  modes and parameters down
                    ┌────────────▼───────────────┐
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

The microcontroller and the app share one WebSocket channel. When a socket connects, the API registers the microcontroller and provisions the greenhouse's sensors and pumps. The device publishes readings and water usage to `/mc-ws/`, the API stores them, and it sends the pump modes and activation parameters back down the same socket. The app renders the readings live and changes the modes through the REST API.

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- DATA FLOWS -->
### The Data Flows

**1. Sensor readings — device → API → app**

```
ESP32 (every 10 s)  ──WS /mc-ws/──▶  API
                                     ├─▶ INSERT sensor_data
                                     └─▶ broadcast ──▶ app updates the dashboard live
```

**2. Pump modes — app → API → device**

```
app dropdown         ──PUT /pump/mode/──▶  API (stores desired mode)
                                            └─▶ WS /mc-ws/ ──▶ ESP32 (switches and runs the pump)
                                                               ESP32 ──WS──▶ API (records the observed mode)
```

**3. Water usage — device → API → app**

```
ESP32 (after a pump runs)  ──WS /mc-ws/──▶  API (stores the watering)
app                                        ──GET /pump/history/──▶ API
```

**4. Weather — outside → AI → pumps**

```
Open-Meteo (hourly)  ──▶  API weather service
                            ├─▶ reads the forecast and the climate
                            └─▶ Gemini reads them with the state of the greenhouse
                                 ├─▶ decides when each pump may water
                                 └─▶ the mode and the parameters go down the socket,
                                     and the ESP32 waters by them
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- SHARED CONTRACT -->
### Shared Contract

These shapes are agreed between all three parts. Changing one means changing the others.

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

`recorded_at` is optional on input; the API stamps it with `datetime.now()` when the device omits it and always returns it as an ISO-8601 string. In REST responses the device's `sensor` field is named `sensor_id` because that is the column name; the WebSocket broadcast keeps the name `sensor`.

**Pump mode ordinals.** The mode is stored as an integer everywhere, and the integers are the ordinals of the Arduino `OperatingMode` enum:

| Ordinal | Mode       | Behaviour             | Litres per run |
|---------|------------|-----------------------|----------------|
|    0    |   `FAST`   | full power for 750 ms |     0.0060     |
|    1    |   `SLOW`   | 47 % PWM for 750 ms   |     0.0028     |
|    2    |   `DRIP`   | 150 ms on, 2.5 s off  |     0.0012     |
|    3    | `SPRINKLE` | not implemented       |       0.0      |

`api/app/modes.py`, `microcontroller/microcontroller.ino` and `frontend/lib/model/pump_info.dart` each hold the same ordered list. The device's own HTTP API speaks mode *names* (`"DRIP"`); the conversion happens in `api/app/services/device_service.py`.

**Pump history.** The device posts `{"pump": 1, "liters": 0.0060}`. The API returns `{"id", "liters", "recorded_at", "pump_id"}`.

**Alert.** `{"message": "...", "severity": "critical|warning|spooky"}`.

**Pump IDs** are `1`, `2`, `3` in the database, on the device, and in the app.

#### Trailing slashes

Every list endpoint is declared with a trailing slash (`/sensor/data/`, `/pump/`, `/pump/mode/`, `/pump/history/`, `/alerts/`). FastAPI redirects a missing slash with a 307, but the WebSocket endpoint is not redirected, so `/mc-ws/` must be requested exactly as written. The only slash-less endpoints are `/health` and `/pump/usage/today`.

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- PROJECT LAYOUT -->
### Project Layout

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

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- BUILT WITH -->
### Built With

* [![Flutter][Flutter.dev]][Flutter-url]
* [![FastAPI][FastAPI.com]][FastAPI-url]
* [![PostgreSQL][PostgreSQL.org]][PostgreSQL-url]
* [![Python][Python.org]][Python-url]
* [![ESP32][ESP32.com]][ESP32-url]
* [![Arduino][Arduino.cc]][Arduino-url]
* [![Google Gemini][Gemini.ai]][Gemini-url]
* [Open-Meteo](https://open-meteo.com)

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- GETTING STARTED -->
## Getting Started

To get a local copy up and running, follow these steps.

### Prerequisites

* [PostgreSQL](https://www.postgresql.org) — the API's database
* [uv](https://docs.astral.sh/uv/) and Python 3.14+ — the API runtime and dependency manager
* [Flutter](https://flutter.dev) 3.44+ (Dart 3.12+) — the dashboard
* [Arduino IDE](https://www.arduino.cc/en/software) with ESP32 board support — the firmware
* A [Google AI Studio](https://aistudio.google.com) API key (optional) — lets Gemini decide how the pumps behave

### Installation

1. Clone the repo
   ```sh
   git clone https://github.com/invalid-code/dbtc-hacktoberfest-2026-g2.git
   cd dbtc-hacktoberfest-2026-g2
   ```

2. Set up the API
   ```sh
   cd api
   uv sync --group dev
   ```

3. Create `api/.env`:
   ```text
   DB_CONN_STR=postgresql+asyncpg://postgres:password@localhost:5432/greenhouse
   FRONTEND_URL=http://localhost:8080
   WEATHER_LATITUDE=14.5995
   WEATHER_LONGITUDE=120.9842
   ```

   `FRONTEND_URL` is the CORS allow-list. It accepts a comma-separated list of origins, and `*` allows everything. `WEATHER_LATITUDE` and `WEATHER_LONGITUDE` say where the greenhouse stands, the weather service asks for the forecast and the climate of that place and adjusts the pumps with it (see the [weather doc](api/README.md#the-weather-service)). The microcontroller needs no address of its own: it keeps the WebSocket open, so the API can reach it anywhere.

   The API logs every request to the console. `LOG_LEVEL` and `LOG_FORMAT` in `api/.env` say how much is logged and whether it is plain text or json, see the [logging doc](api/README.md#logging).

4. Run the migrations and start the service
   ```sh
   cd api
   uv sync --group dev
   uv run alembic upgrade head
   uv run uvicorn app.main:app --host 0.0.0.0 --port 8000
   ```

   The API health check is `GET /health`. Interactive docs are at `/docs`.

5. Start the frontend
   ```sh
   cd frontend
   flutter pub get
   flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000
   ```

   `API_BASE_URL` defaults to `http://localhost:8000`, so the flag is only needed when pointing at a different host. The app derives its WebSocket URL from the same value by rewriting `http` to `ws`.

6. Configure the microcontroller

   Copy the device's local configuration into `microcontroller/secrets.h`:
   ```cpp
   #define SSID "your-wifi"
   #define PASSWORD "your-wifi-password"
   #define WS_SERVER_URL "your-api-host"
   #define WS_SERVER_PORT 443
   #define WS_PATH "/mc-ws/"
   ```

   `secrets.h` is git-ignored. Do not commit it. For a TLS deployment the WebSocket library needs to be configured for `wss://`. The device only needs this socket: readings and water usage go up it, and modes and activation parameters come down it.

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- USAGE -->
## Usage

Open the Flutter dashboard to watch the greenhouse and control the pumps:

| Screen | Path | What it shows |
|---|---|---|
| Dashboard | `/` | Current conditions, water usage chart, pump cards and alerts |
| Watering History | `/watering-history` | Every watering, with pump, time and litres |
| Sensor Readings | `/sensor-reading` | Temperature and moisture trends, with time range filters |

The API serves its interactive documentation at `/docs`, and the health check lives at `GET /health`.

### The Automatic Watering

The API runs a background service that keeps the pumps in step with the weather. It reads the forecast of the next days and the climate of the place from [Open-Meteo](https://open-meteo.com), adds the state of the greenhouse, and asks **Gemini** what every pump should do: whether it may water at all, the moisture threshold it waters at, the minutes it waits between two activations, and the mode it waters in. The mode is what the microcontroller gets, so it is how the amount of water is decided.

Without a `GEMINI_API_KEY` the plain rules decide instead, and the answer is always clamped into its limits before it is stored.

`GET /pump/parameters/` shows what was decided and why. See the [weather doc](api/README.md#the-weather-service) for the details.

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- HALLOWEEN EASTER EGG -->
### Halloween Easter Egg

The microcontroller starts to play tricks as Halloween approaches. In the two weeks before the 31st of October it occasionally replaces a reading with garbled values, and the chance grows every day until it reaches 80% on Halloween night itself. Outside that window the sensors always report the real values.

Garbled readings are flagged with `"garbled": true` so they can be told apart from the real ones. The API stores the flag, raises a spooky alert instead of the usual threshold alerts while a garbled reading is the latest one, and the app marks the readings as haunted. The microcontroller keeps using the real readings for the pump logic, so the greenhouse keeps watering itself.

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- DEPLOYMENT -->
### Deployment

#### The API

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

Set `WEATHER_LATITUDE` and `WEATHER_LONGITUDE` to the place of the greenhouse so the weather service can adjust the pumps, and set `WEATHER_ENABLED=false` to turn that service off. Set `GEMINI_API_KEY` to a Google AI Studio key to let Gemini decide how the pumps behave; without it the rules decide.

#### Automated migrations on `main`

`.github/workflows/migrate-prod-db.yml` runs the Alembic migrations against the production database on every push to `main`: the test suite runs first, then `alembic upgrade head` is applied to the prod database. The workflow can also be started by hand from the Actions tab.

The prod connection string is read from a repository secret, so it never enters the repository. Add it once under **Settings → Secrets and variables → Actions**:

| Secret             | Value                                                                                  |
|--------------------|----------------------------------------------------------------------------------------|
| `PROD_DB_CONN_STR` | The prod database URL, in the same form as `DB_CONN_STR`, e.g. `postgresql+asyncpg://user:password@host/database` |

The secret can also live in a GitHub environment named `production`; the workflow uses that environment, so environment-level protections (required reviewers) apply to the migration.

#### The frontend

Build the Flutter app:

```powershell
cd frontend
flutter build web
```

The API origin is read at runtime from `config.json` next to `index.html`, so the
server hosting the build can change it without rebuilding. `frontend/web/config.json`
is copied into `build/web`; set `API_BASE_URL` there before serving, or replace
`build/web/config.json` after the build:

```json
{
  "API_BASE_URL": "https://your-api.example.com"
}
```

A build-time override is still available, and takes precedence over the file:

```powershell
flutter build web --dart-define=API_BASE_URL=https://your-api.example.com
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- TESTS -->
### Running the Tests

The API tests run against a throwaway SQLite database, they never touch the configured one:

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

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- ROADMAP -->
## Roadmap

- [x] ESP32 firmware that reads the sensors and waters the plants
- [x] FastAPI + PostgreSQL service with a live WebSocket relay
- [x] Flutter dashboard with watering history and sensor trends
- [x] Weather and Gemini-driven pump automation
- [x] Halloween easter egg
- [ ] Add authentication — every REST endpoint and the WebSocket are open; a JWT login system existed once and was removed
- [x] Paginate and filter `GET /sensor/data/` — pages of readings or readings averaged per time unit
- [ ] Show the pump activation parameters in the app — the API exposes them at `GET /pump/parameters/`
- [x] Drive the dashboard pump cards from `GET /pump/` instead of hard-coding three cards
- [ ] Read `observed_mode` and `last_seen_at` in the frontend

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

Distributed under the Apache License 2.0. See `LICENSE` for more information.

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- CONTACT -->
## Contact

Project Link: [https://github.com/invalid-code/dbtc-hacktoberfest-2026-g2](https://github.com/invalid-code/dbtc-hacktoberfest-2026-g2)

Questions or bug reports: [open an issue](https://github.com/invalid-code/dbtc-hacktoberfest-2026-g2/issues/new).

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- ACKNOWLEDGMENTS -->
## Acknowledgments

* [Best-README-Template](https://github.com/othneildrew/Best-README-Template)
* [Open-Meteo](https://open-meteo.com)
* [Google Gemini](https://ai.google.dev)
* [FastAPI](https://fastapi.tiangolo.com)
* [Flutter](https://flutter.dev)
* [Shields.io](https://shields.io)
* [contrib.rocks](https://contrib.rocks)
* [Choose an Open Source License](https://choosealicense.com)

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
[Flutter.dev]: https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white
[Flutter-url]: https://flutter.dev
[FastAPI.com]: https://img.shields.io/badge/FastAPI-009688?style=for-the-badge&logo=fastapi&logoColor=white
[FastAPI-url]: https://fastapi.tiangolo.com
[PostgreSQL.org]: https://img.shields.io/badge/PostgreSQL-4169E1?style=for-the-badge&logo=postgresql&logoColor=white
[PostgreSQL-url]: https://www.postgresql.org
[Python.org]: https://img.shields.io/badge/Python-3776AB?style=for-the-badge&logo=python&logoColor=white
[Python-url]: https://www.python.org
[ESP32.com]: https://img.shields.io/badge/ESP32-E7352C?style=for-the-badge&logo=espressif&logoColor=white
[ESP32-url]: https://www.espressif.com/en/products/socs/esp32
[Arduino.cc]: https://img.shields.io/badge/Arduino-00979D?style=for-the-badge&logo=arduino&logoColor=white
[Arduino-url]: https://www.arduino.cc
[Gemini.ai]: https://img.shields.io/badge/Google%20Gemini-8E75B2?style=for-the-badge&logo=googlegemini&logoColor=white
[Gemini-url]: https://ai.google.dev
