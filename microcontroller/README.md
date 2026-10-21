# Microcontroller

The Arduino sketch for the ESP32. It reads the sensors, waters the plants on
its own, publishes the readings to the API over a WebSocket, reports how much
water it used, and exposes a small HTTP server so the API can change the pump
modes.

- [Hardware](#hardware)
- [secrets.h](#secrets)
- [Libraries](#libraries)
- [The main loop](#the-main-loop)
- [Watering logic](#watering-logic)
- [Pump modes](#pump-modes)
- [Communication](#communication)
- [Halloween easter egg](#halloween-easter-egg)
- [Things to know](#things-to-know)

## Hardware

An ESP32 DevKit with three sensors per zone:

| Peripheral | Pins | Notes |
|---|---|---|
| DHT11 temperature/humidity | 4, 16, 17 | One per zone |
| Capacitive soil moisture | 36, 35, 25 | ADC, raw 0–2800 mapped to 0–100 % |
| Water pump | 25, 26, 27 | Digital output |
| Water level sensor | 39, 32, 26 | ADC, declared but never read |

Zone 1 is sensor 1 / pump 1, zone 2 is sensor 2 / pump 2, and so on.

Two pins are used twice: pin 25 is both pump 1's output and moisture sensor
3's input, and pin 26 is both pump 2's output and water level sensor 3's
input. That only works if the pump output and the analog input are on
separate circuits, but it is worth checking the wiring before trusting zone
3's readings.

## secrets

`microcontroller/secrets.h` holds the local credentials. It is git-ignored and
must never be committed. Create it with:

```cpp
#define SSID "your-wifi"
#define PASSWORD "your-wifi-password"
#define WS_SERVER_URL "your-api-host"
#define WS_SERVER_PORT 443
#define WS_PATH "/mc-ws/"
#define API_SERVER_URL "https://your-api-host"
#define PUMP_HISTORY_PATH "/pump/history/"
```

`WS_PATH` needs the trailing slash — the API does not redirect WebSocket
requests.

## Libraries

| Library | Used for |
|---|---|
| `WiFi.h` | Networking |
| `WebSocketsClient.h` | The WebSocket to the API |
| `WebServer.h` | The `/mode` HTTP server the API polls |
| `ArduinoJson.h` | Building and parsing the JSON payloads |
| `HTTPClient.h` | Posting the water usage |
| `DHT.h` | The DHT11 sensors |
| `freertos/*` | The queue and task that keep the HTTP POST off the main loop |

## The main loop

`loop()` runs continuously and does three things:

1. `webSocket.loop()` — keeps the socket alive and pumps its reconnect timer.
2. `deviceServer.handleClient()` — serves the `/mode` requests.
3. Every 10 seconds, reads each zone and publishes it.

Each 10-second cycle, for each of the three zones:

```cpp
int moistureValue = analogRead(MOISTURE_PIN_1);
int moisturePercent = map(moistureValue, MOISTURE_LOW_VAL, MOISTURE_HIGH_VAL, 0, 100);
moisturePercent = constrain(moisturePercent, 0, 100);

float temp = tempSensor1.readTemperature();
float humidity = tempSensor1.readHumidity();

publishSensorReading(1, moisturePercent, temp, humidity);
openPump(1, moisturePercent, temp, humidity, curMode1);
```

The loop also reconnects to Wi-Fi if the connection drops.

`setup()` starts the serial port at 115200, seeds the RNG, syncs the clock
from `pool.ntp.org`, connects to Wi-Fi, opens the WebSocket, creates the
usage queue and its task, starts the HTTP server, initialises the DHT sensors
and sets the pin modes.

## Watering logic

`openPump()` runs a pump when the soil is dry:

```cpp
void openPump(int pumpId, int moisturePercent, float tempValue, float humidityValue, int curMode) {
  if (moisturePercent <= 30 && tempValue > 30.0 && humidityValue > 70.0) {
    activatePumpMode(pumpId, pumpPinFor(pumpId), curMode);
  } else if (moisturePercent <= 30) {
    activatePumpMode(pumpId, pumpPinFor(pumpId), curMode);
  }
}
```

Both branches do the same thing — the second one is a superset of the first,
so the temperature and humidity conditions have no effect.

The pump decision always uses the **real** readings, even when a garbled
reading is being published. The greenhouse keeps watering itself during the
easter egg.

## Pump modes

The modes are an enum whose ordinals are the integers stored in the database:

```cpp
enum OperatingMode { FAST, SLOW, DRIP, SPRINKLE };
```

| Mode | Behaviour | Duration | Litres |
|---|---|---|---|
| `FAST` | `digitalWrite(HIGH)` | 750 ms | 0.0060 |
| `SLOW` | `analogWrite(pin, 120)` — 47 % PWM | 750 ms | 0.0028 |
| `DRIP` | 150 ms on, then 2.5 s off | 150 ms | 0.0012 |
| `SPRINKLE` | Nothing, not implemented | — | 0.0 |

The litre figures come from `PUMP_LITRES_PER_SECOND = 0.008`, scaled by the
run time and, for `SLOW`, by the PWM duty cycle.

The current mode of each pump is kept in `curMode1`, `curMode2`, `curMode3`.

## Communication

### Outbound: readings over the WebSocket

`publishSensorReading()` builds the payload with ArduinoJson and sends it
with `webSocket.sendTXT()`:

```json
{
  "sensor": 1,
  "moisture_level": 42,
  "temperature": 23.5,
  "humidity": 78,
  "garbled": false
}
```

The socket reconnects every 5 seconds. The device never reads from the
WebSocket; `webSocketEvent()` only prints what arrives.

### Outbound: water usage over HTTP

After a pump actually runs, `reportWaterUsage()` puts a report on a FreeRTOS
queue. A separate task pops it and posts it, so the HTTP request never blocks
the sensor loop:

```json
{ "pump": 1, "liters": 0.0060 }
```

The queue holds 8 entries. A report is dropped with a log line if the queue is
full.

### Inbound: the `/mode` server

The ESP32 runs a `WebServer` on port 80 with two handlers:

| Method | Path | Request | Response |
|---|---|---|---|
| GET | `/mode` | — | `{"modes":{"1":"FAST","2":"SLOW","3":"DRIP"}}` |
| POST | `/mode` | `{"pump": 1, "mode": "DRIP"}` | `{"pump":1,"mode":"DRIP"}` |

`POST /mode` also accepts form arguments instead of a JSON body. It answers
`400` with `{"error":"pump and mode are required"}` when the pump or the mode
is missing, and `404` with `{"error":"unknown pump"}` for a pump that is not
1, 2 or 3.

### API device polling

The API is the one that drives the modes, not the device. Set `DEVICE_URL` to
the ESP32's address to enable it:

```text
DEVICE_URL=http://192.168.1.50
```

The API then polls `GET {DEVICE_URL}/mode` every
`DEVICE_POLL_INTERVAL_SECONDS` (5 by default), records what the device reports
in `pump_mode.observed_mode`, and pushes the desired mode with
`POST {DEVICE_URL}/mode` whenever the two disagree. The ESP32 must be
reachable from wherever the API runs.

## Halloween easter egg

`configTime()` syncs the clock, then:

1. `daysUntilHalloween()` counts the days to the 31st of October.
2. `halloweenHaunting()` returns `0` outside the 14-day window, and otherwise
   ramps linearly from `0` to `1` as the date approaches.
3. `shouldSendGarbledData()` rolls against `haunting * 0.8`, so the chance of
   a garbled reading reaches 80% on Halloween night.
4. `garbledReading()` invents nonsense: moisture and humidity between 101 and
   999, temperature between −50 °C and 150 °C.

A garbled reading is published with `"garbled": true`. The API stores the flag,
raises a spooky alert instead of the threshold alerts, and the app shows a
"haunted" banner. The pump logic keeps using the real values.

## Things to know

- **The water level sensors are never read.** The pins are declared and
  `pinMode`d, but no `analogRead` touches them. The `humidity` value in the
  payload comes from the DHT11, not from these sensors.
- **`SPRINKLE` does nothing.** The function is an empty stub.
- **`humidity` is sent as a float** but the API schema declares it as an `int`.
  Pydantic coerces it only when it has no fractional part, so a fractional
  humidity would fail validation and drop the WebSocket connection.
- **Pins 25 and 26 are double-booked**, as described in the hardware section.
- **The `openPump()` branches are redundant**, as described in the watering
  section.
- **`secrets.h` and `api/.env` hold live credentials.** Both are git-ignored.
  Check they never get committed.
