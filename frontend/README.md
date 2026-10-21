# Frontend

The Flutter dashboard for the greenhouse. It shows the live sensor conditions,
the pump controls, the watering history and the sensor trends, and it sends
pump-mode changes back to the API.

- [Stack](#stack)
- [Running it](#running-it)
- [Architecture](#architecture)
- [Layout](#layout)
- [Routing](#routing)
- [State management](#state-management)
- [Data layer](#data-layer)
- [Screens](#screens)
- [Design system](#design-system)
- [Tests](#tests)
- [Things to know](#things-to-know)

## Stack

| Concern | Choice |
|---|---|
| Language | Dart, SDK `^3.12.2` |
| Framework | Flutter, `>=3.44.0` |
| Routing | `go_router` ^18.1.0 |
| HTTP | `http` ^1.5.0 |
| WebSockets | `web_socket_channel` ^3.0.3 |
| State | Flutter's own `ChangeNotifier` + `ListenableBuilder`, no state package |
| Charts | Hand-drawn `CustomPainter`s, no charting library |
| Models | Hand-written `fromJson`, no code generation |
| Lints | `flutter_lints` ^6.0.0 |

## Running it

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

`frontend/config.json` holds a local copy of the same value for convenience.
Nothing reads it — it is a git-ignored scratch file. The real configuration
surface is the `--dart-define` flag.

## Architecture

Feature-first, with a shared core:

```
lib/
├── main.dart            entry point, theme, dependency-injection seams
├── router/              go_router setup + route path constants
├── model/               models shared between features (alert, pump)
├── core/
│   ├── network/         api_client.dart (REST), sensor_ws.dart (WebSocket)
│   └── widgets/         panels, sidebar, charts, formatters
└── features/
    ├── home/            dashboard
    ├── history/         watering history
    └── sensors/         sensor trends
```

Each feature is split into `data/` (models), `presentation/` (screens) and
`presentation/viewmodel/` (state) and `presentation/widgets/` (feature-local
UI).

The dependency injection is deliberately minimal: `GreenhouseApp` takes two
optional factory functions, `api` and `feed`. The router calls them when it
builds a screen. In production they are `null` and the view models construct
real clients; in tests they return fakes.

```dart
GreenhouseApp(
  api: () => fakeApi(response),
  feed: FakeFeed.new,
)
```

## Layout

| Path | What it is |
|---|---|
| `lib/main.dart` | `GreenhouseApp`, the theme, the DI seams |
| `lib/router/app_router.dart` | `buildRouter()`, the three routes |
| `lib/router/routes.dart` | `AppRoutes` path constants |
| `lib/model/alert.dart` | `Alert` — message and severity |
| `lib/model/pump_info.dart` | `PumpInfo`, the mode labels and `pumpModeLabel()` |
| `lib/core/network/api_client.dart` | `GreenhouseApi`, the HTTP client, `GreenhouseSnapshot` |
| `lib/core/network/sensor_ws.dart` | `SensorFeed`, the live WebSocket feed |
| `lib/core/widgets/panel.dart` | `Panel`, the shared card, `panelContentHeight` |
| `lib/core/widgets/conditions_card.dart` | `ConditionsCard`, the metrics grid and the spooky banner |
| `lib/core/widgets/side_bar.dart` | `SideBar`, the only navigation control |
| `lib/core/widgets/chart_painter.dart` | `ChartPainter`, the monthly usage chart |
| `lib/core/widgets/sort_menu.dart` | `SortMenu`, the newest/oldest toggle |
| `lib/core/widgets/empty_history.dart` | `EmptyHistory`, the empty state |
| `lib/core/widgets/formatting.dart` | Litres, times and dates |
| `lib/features/home/presentation/home_view.dart` | The dashboard screen |
| `lib/features/home/presentation/viewmodel/home_view_model.dart` | `HomeViewModel` |
| `lib/features/home/presentation/widgets/` | `PumpCard`, `AlertsCard`, `HistorySummary`, `UsageChart` |
| `lib/features/history/data/pump_history_entry.dart` | `PumpHistoryEntry` |
| `lib/features/history/presentation/watering_history_view.dart` | The history screen |
| `lib/features/history/presentation/viewmodel/watering_history_view_model.dart` | `WateringHistoryViewModel` |
| `lib/features/sensors/data/sensor_reading.dart` | `SensorReading` |
| `lib/features/sensors/presentation/sensor_readings_view.dart` | The trends screen |
| `lib/features/sensors/presentation/viewmodel/sensor_readings_view_model.dart` | `SensorReadingsViewModel` |
| `lib/features/sensors/presentation/widgets/line_chart_painter.dart` | `LineChartPainter` |

## Routing

`go_router`, three paths, declared in `lib/router/routes.dart`:

| Constant | Path | Screen |
|---|---|---|
| `AppRoutes.home` | `/` | `HomeView` |
| `AppRoutes.wateringHistory` | `/watering-history` | `WateringHistoryView` |
| `AppRoutes.sensorReading` | `/sensor-reading` | `SensorReadingsView` |

There are no route names, no parameters, no redirects and no nested routes.
`SideBar` is the only navigation control in the app; it calls `context.go()`,
so navigation replaces the screen rather than stacking it. There is no app bar
and no back button.

## State management

No third-party state package. The pattern is **view model + `ChangeNotifier` +
`ListenableBuilder`**:

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

- **A screen owns its view model.** It creates it in `initState`, calls
  `start()`, and disposes it in `dispose()`.
- **`null` means loading, a separate `bool` means failed.** `HomeViewModel`
  has `snapshot`, `todayUsageLiters`, `alerts`, `monthlyUsage`, `history` and
  four matching `...Failed` flags. The widgets pick the right empty or error
  state from those two pieces of information.
- **Errors are caught, never rethrown.** Every API call is wrapped in a
  `try/catch` that flips a flag instead of propagating, so one failing
  endpoint does not blank the screen.
- **Updates are local.** `updatePumpMode` writes to the API and then applies
  the new mode to the in-memory snapshot.

## Data layer

There is no separate repository layer. `GreenhouseApi` is both the HTTP client
and the repository.

`lib/core/network/api_client.dart`:

| Method | Request | Returns |
|---|---|---|
| `loadSensorReadings()` | `GET /sensor/data/` | `List<SensorReading>`, sorted oldest first |
| `loadLatestSensorReading()` | `GET /sensor/data/` | The newest `SensorReading`, or `null` |
| `loadPumps()` | `GET /pump/` | `List<PumpInfo>` |
| `loadPumpModes()` | `GET /pump/mode/` | `Map<int, int>` of pump id → mode |
| `updatePumpMode(pump, mode)` | `PUT /pump/mode/` | — |
| `loadPumpHistory()` | `GET /pump/history/` | `List<PumpHistoryEntry>` |
| `loadTodayWaterUsage()` | `GET /pump/usage/today` | `double` litres |
| `loadAlerts()` | `GET /alerts/` | `List<Alert>` |

Every request has a 10-second timeout and sends `Accept: application/json`. A
non-2xx status throws, and a body that is not the expected JSON shape throws
a `FormatException`.

`lib/core/network/sensor_ws.dart` holds `SensorFeed`. It derives the
WebSocket URL from the API base URL by rewriting `http` to `ws`, connects to
`/mc-ws/`, and republishes the readings on a broadcast `Stream`. It
reconnects 5 seconds after an error or a disconnect, and it ignores any
message that is not a sensor reading.

## Screens

### Dashboard (`/`)

- **Current Conditions** — today's water usage, soil moisture, humidity and
  temperature, in a grid that goes 4 → 2 → 1 columns as the width shrinks.
- **Water Usage History** — a hand-drawn line chart of the last 12 months.
- **History Summary** — today's and yesterday's waterings, side by side with
  the chart on wide screens.
- **Sensor Status** — a card per pump with a mode dropdown and a start/stop
  button.
- **Alerts** — the active alerts, styled by severity.

The dashboard loads everything in parallel on `start()` and then keeps the
sensor reading up to date over the WebSocket. A reading that arrives over the
socket replaces only the sensor in the snapshot; the pumps are kept.

Changing a pump **mode** updates the UI optimistically and rolls back with a
snack bar if the `PUT` fails. The **start/stop button is local only** — it
toggles a `running` flag in the widget's state and never reaches the API, so
it does not actually stop a pump.

### Watering History (`/watering-history`)

The full list of waterings, newest first by default, with a sort toggle in
the panel header. Each row shows the pump, the date and time, and the litres.

### Sensor Readings (`/sensor-reading`)

The current conditions at the top, then two trend panels — temperature and
moisture — drawn with `ChartPainter` and `LineChartPainter`. The charts
normalise their values before painting: moisture is divided by 100 and
temperature by 50, both clamped to 0–1.

This screen's `ConditionsCard` shows only the sensor, so today's water usage
renders as `—`.

## Design system

There is no theme package. The theme is inline in `lib/main.dart`: Material 3
with a green seed colour (`0xff2d7600`), a pale green background
(`0xfff0fae7`) and Roboto.

The rest of the palette is hard-coded where it is used:

| Colour | Value | Used for |
|---|---|---|
| Sage | `0xffccdec3` | Panels and section backgrounds |
| White | `Colors.white` | Cards, the sidebar |
| Green | `0xff007300` | Chart lines |
| Dark green | `0xff384b2c` | The "start" button |
| Dark red | `0xff760202` | The "stop" button, critical alerts |
| Purple | `0xff6a1b9a` | The spooky banner and spooky alerts |

`Panel` is the shared card. `panelContentHeight` is a shared constant
(`340.0`) so every panel keeps the same height whether it has data or not.

`core/widgets/formatting.dart` holds the formatters: `formatLiters`,
`formatTime`, `formatRecordedAt`, `pumpLabel`. Dates are formatted by hand —
the `intl` package is not a dependency.

## Tests

```powershell
cd frontend
flutter test
```

The suite covers 38 tests:

| File | Tests | What it covers |
|---|---|---|
| `test/api_client_test.dart` | 4 | JSON parsing, the garbled flag, the requested paths, that failures throw |
| `test/models_test.dart` | 10 | Every model's `fromJson`, including the fallbacks for missing and broken values |
| `test/sensor_feed_test.dart` | 6 | Parsing socket messages, ignoring non-readings, the feed stops after `dispose()` |
| `test/view_models_test.dart` | 11 | Loading state, per-endpoint failure flags, live updates, mode updates, monthly normalisation |
| `test/widget_test.dart` | 7 | The three screens, navigation, the empty and error states, the spooky banner |

`test/support/fakes.dart` holds the shared harness:

- `FakeFeed` — a `SensorFeed` with a no-op `connect()`.
- `responseFor(path)` — a happy-path fixture for every REST endpoint.
- `emptyResponseFor(path)` — the same endpoints with empty collections.
- `garbledResponseFor(path)` — a garbled reading and a spooky alert.
- `failingResponseFor(path)` — a 500 for everything.
- `fakeApi(response)` — a `GreenhouseApi` over a `MockClient` that can record
  the requests it received.
- `waitFor(condition)` — polls until a condition holds or the deadline passes.

The widget tests mount the real `GreenhouseApp` with these fakes, so no
network or socket is touched.

## Things to know

- **The pump list is hard-coded** to three cards in `home_view.dart` instead
  of iterating over the pumps the API returns. `pumpIdFor(index)` and
  `pumpModeFor(index)` fall back to `index + 1` when the snapshot is missing.
- **`core` depends on `features`.** `core/widgets/formatting.dart` imports
  the history model, and `core/network/api_client.dart` imports the feature
  and shared models. The layering is inverted in two places.
- **Models live in two places.** `lib/model/` holds the shared ones, the
  feature `data/` folders hold the rest.
- **`GreenhouseSnapshot` sits in the network layer** even though the view
  models and `ConditionsCard` consume it.
- **`cupertino_icons` is declared but never imported.**
- **The `/gemini/*` endpoints are not used**, so the app has no AI screen.
