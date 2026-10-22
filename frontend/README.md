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
  <a href="https://github.com/invalid-code/dbtc-hacktoberfest-2026-g2/tree/main/frontend">
    <img src="https://img.shields.io/badge/Frontend-Flutter-02569B?style=for-the-badge" alt="Frontend" height="40">
  </a>

  <h3 align="center">Frontend</h3>

  <p align="center">
    The Flutter dashboard for the greenhouse: live conditions, pump controls, watering history and sensor trends.
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
      <a href="#architecture">Architecture</a>
      <ul>
        <li><a href="#layout">Layout</a></li>
        <li><a href="#routing">Routing</a></li>
        <li><a href="#state-management">State Management</a></li>
        <li><a href="#data-layer">Data Layer</a></li>
        <li><a href="#design-system">Design System</a></li>
      </ul>
    </li>
    <li>
      <a href="#usage">Usage</a>
      <ul>
        <li><a href="#screens">Screens</a></li>
        <li><a href="#time-range-filter">Time Range Filter</a></li>
      </ul>
    </li>
    <li><a href="#tests">Tests</a></li>
    <li><a href="#roadmap">Roadmap</a></li>
    <li><a href="#contributing">Contributing</a></li>
    <li><a href="#license">License</a></li>
    <li><a href="#contact">Contact</a></li>
    <li><a href="#acknowledgments">Acknowledgments</a></li>
  </ol>
</details>



<!-- ABOUT THE PROJECT -->
## About The Project

The Flutter dashboard for the greenhouse. It shows the live sensor conditions, the pump controls, the watering history and the sensor trends, and it sends pump-mode changes back to the API.

Part of [Greenhouse IoT](../README.md). The other components are the [FastAPI service](../api/README.md) and the [ESP32 firmware](../microcontroller/README.md).

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- BUILT WITH -->
### Built With

* [![Flutter][Flutter.dev]][Flutter-url]
* [![Dart][Dart.dev]][Dart-url]
* [go_router](https://pub.dev/packages/go_router)
* [Material 3](https://m3.material.io)

|  Concern   |                                 Choice                                 |
|------------|------------------------------------------------------------------------|
| Language   | Dart, SDK `^3.12.2`                                                    |
| Framework  | Flutter, `>=3.44.0`                                                    |
| Routing    | `go_router` ^18.1.0                                                    |
| HTTP       | `http` ^1.5.0                                                          |
| WebSockets | `web_socket_channel` ^3.0.3                                            |
| State      | Flutter's own `ChangeNotifier` + `ListenableBuilder`, no state package |
| Charts     | Hand-drawn `CustomPainter`s, no charting library                       |
| Models     | Hand-written `fromJson`, no code generation                            |
| Lints      | `flutter_lints` ^6.0.0                                                 |

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- GETTING STARTED -->
## Getting Started

To get the app running locally, follow these steps.

### Prerequisites

* [Flutter](https://flutter.dev) 3.44+ with Dart `^3.12.2`
* A running API at `http://localhost:8000` — see the [API doc](../api/README.md)
* Chrome (or another Flutter target) for `flutter run`

### Installation

```powershell
cd frontend
flutter pub get
flutter run -d chrome
```

The API base URL is a compile-time constant:

```dart
const _apiBaseUrlRaw = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:8000',
);
```

Override it at build or run time:

```powershell
flutter run -d chrome --dart-define=API_BASE_URL=https://your-api.example.com
```

`frontend/config.json` holds a local copy of the same value for convenience. Nothing reads it — it is a git-ignored scratch file. The real configuration surface is the `--dart-define` flag.

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- ARCHITECTURE -->
## Architecture

Feature-first, with a shared core:

```
lib/
├── main.dart            entry point, theme, dependency-injection seams
├── router/              go_router setup + route path constants
├── model/               models shared between features (alert, pump)
├── core/
│   ├── models/          time_range.dart, chart_series.dart
│   ├── network/         api_client.dart (REST), sensor_ws.dart (WebSocket)
│   └── widgets/         panels, sidebar, charts, formatters
└── features/
    ├── home/            dashboard
    ├── history/         watering history
    └── sensors/         sensor trends
```

Each feature is split into `data/` (models), `presentation/` (screens) and `presentation/viewmodel/` (state) and `presentation/widgets/` (feature-local UI).

The dependency injection is deliberately minimal: `GreenhouseApp` takes two optional factory functions, `api` and `feed`. The router calls them when it builds a screen. In production they are `null` and the view models construct real clients; in tests they return fakes.

```dart
GreenhouseApp(
  api: () => fakeApi(response),
  feed: FakeFeed.new,
)
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- LAYOUT -->
### Layout

|                                      Path                                      |                        What it is                        |
|--------------------------------------------------------------------------------|----------------------------------------------------------|
| `lib/main.dart`                                                                | `GreenhouseApp`, the theme, the DI seams                 |
| `lib/router/app_router.dart`                                                   | `buildRouter()`, the three routes                        |
| `lib/router/routes.dart`                                                       | `AppRoutes` path constants                               |
| `lib/model/alert.dart`                                                         | `Alert` — message and severity                           |
| `lib/model/pump_info.dart`                                                     | `PumpInfo`, the mode labels and `pumpModeLabel()`        |
| `lib/core/network/api_client.dart`                                             | `GreenhouseApi`, the HTTP client, `GreenhouseSnapshot`   |
| `lib/core/network/sensor_ws.dart`                                              | `SensorFeed`, the live WebSocket feed                    |
| `lib/core/models/time_range.dart`                                              | `TimeRange`, the time ranges a graph is filtered by      |
| `lib/core/models/chart_series.dart`                                            | `ChartPoint`, `ChartBucket`, `ChartSeries.group`         |
| `lib/core/widgets/panel.dart`                                                  | `Panel`, the shared card, `panelContentHeight`           |
| `lib/core/widgets/conditions_card.dart`                                        | `ConditionsCard`, the metrics grid and the spooky banner |
| `lib/core/widgets/side_bar.dart`                                               | `SideBar`, the only navigation control                   |
| `lib/core/widgets/chart_painter.dart`                                          | `ChartPainter`, the line chart                           |
| `lib/core/widgets/scrollable_chart.dart`                                       | `ScrollableChart`, the line chart that scrolls sideways  |
| `lib/core/widgets/sort_menu.dart`                                              | `SortMenu`, the newest/oldest toggle                     |
| `lib/core/widgets/time_range_filter.dart`                                      | `TimeRangeFilter`, the time range chip                   |
| `lib/core/widgets/empty_history.dart`                                          | `EmptyHistory`, the empty state                          |
| `lib/core/widgets/formatting.dart`                                             | Litres, times and dates                                  |
| `lib/features/home/presentation/home_view.dart`                                | The dashboard screen                                     |
| `lib/features/home/presentation/viewmodel/home_view_model.dart`                | `HomeViewModel`                                          |
| `lib/features/home/presentation/widgets/`                                      | `PumpCard`, `AlertsCard`, `HistorySummary`, `UsageChart` |
| `lib/features/history/data/pump_history_entry.dart`                            | `PumpHistoryEntry`                                       |
| `lib/features/history/presentation/watering_history_view.dart`                 | The history screen                                       |
| `lib/features/history/presentation/viewmodel/watering_history_view_model.dart` | `WateringHistoryViewModel`                               |
| `lib/features/sensors/data/sensor_reading.dart`                                | `SensorReading`                                          |
| `lib/features/sensors/data/sensor_bucket.dart`                                 | `SensorBucket`, the averages of a unit of time           |
| `lib/features/sensors/presentation/sensor_readings_view.dart`                  | The trends screen                                        |
| `lib/features/sensors/presentation/viewmodel/sensor_readings_view_model.dart`  | `SensorReadingsViewModel`                                |

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- ROUTING -->
### Routing

`go_router`, three paths, declared in `lib/router/routes.dart`:

| Constant | Path | Screen |
|---|---|---|
| `AppRoutes.home` | `/` | `HomeView` |
| `AppRoutes.wateringHistory` | `/watering-history` | `WateringHistoryView` |
| `AppRoutes.sensorReading` | `/sensor-reading` | `SensorReadingsView` |

There are no route names, no parameters, no redirects and no nested routes. `SideBar` is the only navigation control in the app; it calls `context.go()`, so navigation replaces the screen rather than stacking it. There is no app bar and no back button.

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- STATE MANAGEMENT -->
### State Management

No third-party state package. The pattern is **view model + `ChangeNotifier` + `ListenableBuilder`**:

```dart
class _HomeViewState extends State<HomeView> {
  late final HomeViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = HomeViewModel(api: widget.api, feed: widget.feed)..start();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _viewModel,
    builder: (context, _) => ...,
  );
}
```

The rules the codebase follows:

- **A screen owns its view model.** It creates it in `initState`, calls `start()`, and disposes it in `dispose()`.
- **`null` means loading, a separate `bool` means failed.** `HomeViewModel` has `snapshot`, `todayUsageLiters`, `alerts`, `usageBuckets`, `history` and four matching `...Failed` flags. The widgets pick the right empty or error state from those two pieces of information.
- **Errors are caught, never rethrown.** Every API call is wrapped in a `try/catch` that flips a flag instead of propagating, so one failing endpoint does not blank the screen.
- **Updates are local.** `updatePumpMode` writes to the API and then applies the new mode to the in-memory snapshot.

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- DATA LAYER -->
### Data Layer

There is no separate repository layer. `GreenhouseApi` is both the HTTP client and the repository.

`lib/core/network/api_client.dart`:

|            Method            |         Request         |                  Returns                   |
|------------------------------|-------------------------|--------------------------------------------|
| `loadSensorReadings({limit, offset, since, until})` | `GET /sensor/data/` | `List<SensorReading>`, sorted oldest first |
| `loadSensorBuckets(range)`   | `GET /sensor/data/?bucket=<unit>` | `List<SensorBucket>`, averaged per unit, oldest first |
| `loadLatestSensorReading()`  | `GET /sensor/data/?limit=1` | The newest `SensorReading`, or `null`  |
| `loadPumps()`                | `GET /pump/`            | `List<PumpInfo>`                           |
| `loadPumpModes()`            | `GET /pump/mode/`       | `Map<int, int>` of pump id → mode          |
| `updatePumpMode(pump, mode)` | `PUT /pump/mode/`       | —                                          |
| `loadPumpHistory()`          | `GET /pump/history/`    | `List<PumpHistoryEntry>`                   |
| `loadTodayWaterUsage()`      | `GET /pump/usage/today` | `double` litres                            |
| `loadAlerts()`               | `GET /alerts/`          | `List<Alert>`                              |

Every request has a 10-second timeout and sends `Accept: application/json`. A non-2xx status throws, and a body that is not the expected JSON shape throws a `FormatException`.

`lib/core/network/sensor_ws.dart` holds `SensorFeed`. It derives the WebSocket URL from the API base URL by rewriting `http` to `ws`, connects to `/mc-ws/`, and republishes the readings on a broadcast `Stream`. It reconnects 5 seconds after an error or a disconnect, and it ignores any message that is not a sensor reading.

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- DESIGN SYSTEM -->
### Design System

There is no theme package. The theme is inline in `lib/main.dart`: Material 3 with a green seed colour (`0xff2d7600`), a pale green background (`0xfff0fae7`) and Roboto.

The rest of the palette is hard-coded where it is used:

|   Colour   |     Value      |              Used for               |
|------------|----------------|-------------------------------------|
| Sage       | `0xffccdec3`   | Panels and section backgrounds      |
| White      | `Colors.white` | Cards, the sidebar                  |
| Green      | `0xff007300`   | Chart lines                         |
| Dark green | `0xff384b2c`   | The "start" button                  |
| Dark red   | `0xff760202`   | The "stop" button, critical alerts  |
| Purple     | `0xff6a1b9a`   | The spooky banner and spooky alerts |

`Panel` is the shared card. `panelContentHeight` is a shared constant (`340.0`) so every panel keeps the same height whether it has data or not.

`core/widgets/formatting.dart` holds the formatters: `formatLiters`, `formatTime`, `formatRecordedAt`, `pumpLabel`. Dates are formatted by hand — the `intl` package is not a dependency.

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- USAGE -->
## Usage

### Screens

#### Dashboard (`/`)

- **Current Conditions** — today's water usage, soil moisture, humidity and temperature, in a grid that goes 4 → 2 → 1 columns as the width shrinks.
- **Water Usage History** — a hand-drawn line chart of the water used, with a time range filter in the panel header.
- **History Summary** — today's and yesterday's waterings, side by side with the chart on wide screens.
- **Sensor Status** — a card per pump with a mode dropdown and a start/stop button.
- **Alerts** — the active alerts, styled by severity.

The dashboard loads everything in parallel on `start()` and then keeps the sensor reading up to date over the WebSocket. A reading that arrives over the socket replaces only the sensor in the snapshot; the pumps are kept.

Changing a pump **mode** updates the UI optimistically and rolls back with a snack bar if the `PUT` fails. The **start/stop button is local only** — it toggles a `running` flag in the widget's state and never reaches the API, so it does not actually stop a pump.

#### Watering History (`/watering-history`)

The full list of waterings, newest first by default, with a sort toggle in the panel header. Each row shows the pump, the date and time, and the litres.

#### Sensor Readings (`/sensor-reading`)

The current conditions at the top, then two trend panels — temperature and moisture — drawn with `ScrollableChart`. Each panel has its own time range filter. The charts scale their values before painting: moisture is scaled to 100 and temperature to 50, both clamped to the height of the chart.

The screen opens the live feed: a reading joins the real-time graphs right away, and the ranges that show averaged buckets fetch them again at most once every five seconds.

This screen's `ConditionsCard` shows only the sensor, so today's water usage renders as `—`.

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- TIME RANGE FILTER -->
### Time Range Filter

Every graph can be filtered by a time range. The filter is a chip in the panel header (`TimeRangeFilter`), the same style as the sort toggle of the history screen.

| Range      | Points | Window              | Label of a point |
|------------|--------|---------------------|------------------|
| `realTime` | 60     | The latest readings | `15:28`          |
| `minute`   | 60     | The last hour       | `15:28`          |
| `hour`     | 24     | The last day        | `15:00`          |
| `day`      | 30     | The last 30 days    | `OCT 20`         |
| `week`     | 12     | The last 12 weeks   | `OCT 19`         |
| `month`    | 12     | The last 12 months  | `OCT`            |
| `year`     | 5      | The last 5 years    | `2026`           |

**Real-time is the default.** It does not group the readings by a unit of time: every reading is a point of its own and the latest 60 of them are plotted. The trend charts of the sensor readings screen are live — the screen opens the WebSocket feed and a reading that comes in joins the readings and the graphs. The water usage chart has no live feed, the API only sends the sensor readings over the socket, so it shows the latest waterings one point each.

The real time range is the only one that downloads raw readings: the view model asks the API for the latest 60 (`?limit=60`). Every other range asks the API to average the readings per unit first (`?bucket=<unit>&limit=<slots + 1>`), so the app only downloads the points the graph draws — at most a couple of dozen rows instead of every reading behind them. One extra unit is asked for, so a reading that lands right at the edge of the window is not lost.

1. `ChartSeries.group` places the points in the window: the ones outside are dropped and the rest keep the place of their unit (its `fraction`, 0 at the left edge and 1 at the right one). The water usage of a bucket is added up (`BucketMode.sum`); the sensor buckets arrive already averaged by the API, so `BucketMode.average` leaves them untouched. The real time range skips the grouping, every reading is a point of its own.
2. The buckets that hold no point are left out, so the graph only shows the units with data. A unit without data still leaves a gap on the axis.
3. The view models keep the range and rebuild the buckets when it changes. `HomeViewModel` has `usageRange`, `SensorReadingsViewModel` has `temperatureRange` and `moistureRange`.
4. `SensorReadingsViewModel` caches the series of every range it fetched and fetches it the first time the range is selected. The live feed updates the real time graph right away and refreshes the cached series at most once every five seconds, so a burst of readings costs a single request.

The chart does not squeeze the whole range into the screen. Every unit of the range gets 50 pixels on the x axis (`ScrollableChart`), so a wider range is read by scrolling sideways — the graph opens at the newest data and follows it while the reader stays at the end. The labels are drawn where their unit sits and dropped when they would sit closer than 50 pixels to the last one. The real time range sizes the axis by its readings: one place each, the labels tell when they were taken.

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- TESTS -->
## Tests

```powershell
cd frontend
flutter test
```

The suite covers 62 tests:

| File                          | Tests |                                        What it covers                                        |
|-------------------------------|-------|----------------------------------------------------------------------------------------------|
| `test/api_client_test.dart`   |   5   | JSON parsing, the garbled flag, the requested paths and pages, that failures throw           |
| `test/chart_series_test.dart` |  13   | Grouping the points into the buckets of a range, the real time points, the labels of the axis |
| `test/models_test.dart`       |  10   | Every model's `fromJson`, including the fallbacks for missing and broken values              |
| `test/scrollable_chart_test.dart` | 4 | The chart scrolls to the newest data, fits short ranges, follows new data only at the end     |
| `test/sensor_feed_test.dart`  |   6   | Parsing socket messages, ignoring non-readings, the feed stops after `dispose()`             |
| `test/view_models_test.dart`  |  16   | Loading state, per-endpoint failure flags, live updates, mode updates, the time ranges      |
| `test/widget_test.dart`       |   8   | The three screens, navigation, the empty and error states, the spooky banner, the filter    |

`test/support/fakes.dart` holds the shared harness:

- `FakeFeed` — a `SensorFeed` with a no-op `connect()`.
- `responseFor(uri)` — a happy-path fixture for every REST endpoint.
- `emptyResponseFor(uri)` — the same endpoints with empty collections.
- `garbledResponseFor(uri)` — a garbled reading and a spooky alert.
- `failingResponseFor(uri)` — a 500 for everything.
- `fakeApi(response)` — a `GreenhouseApi` over a `MockClient` that can record the requests it received.
- `waitFor(condition)` — polls until a condition holds or the deadline passes.

The fixtures take the whole `Uri`, so a test can answer the same path differently for a page of readings and for an averaged series. The widget tests mount the real `GreenhouseApp` with these fakes, so no network or socket is touched.

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- ROADMAP -->
## Roadmap

- [x] Three screens with `go_router` navigation
- [x] Live sensor readings over the WebSocket
- [x] Time range filters on every chart
- [x] Shared panels, charts and formatters
- [ ] Drive the dashboard pump cards from `GET /pump/` instead of hard-coding three cards
- [ ] Fix the layering inversion where `core` imports `features`
- [ ] Keep the shared models in one place (`lib/model/` and the feature `data/` folders)
- [ ] Move `GreenhouseSnapshot` out of the network layer
- [ ] Remove the unused `cupertino_icons` dependency
- [ ] Add a screen for the pump activation parameters (`GET /pump/parameters/`)
- [ ] Make the start/stop button reach the API — it is local only today
- [ ] Add a live feed for water usage — only sensor readings are broadcast today

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
* [Flutter](https://flutter.dev)
* [Dart](https://dart.dev)
* [go_router](https://pub.dev/packages/go_router)
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
[Flutter.dev]: https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white
[Flutter-url]: https://flutter.dev
[Dart.dev]: https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white
[Dart-url]: https://dart.dev
