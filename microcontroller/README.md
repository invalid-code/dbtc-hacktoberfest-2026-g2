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
  <a href="https://github.com/invalid-code/dbtc-hacktoberfest-2026-g2/tree/main/microcontroller">
    <img src="https://img.shields.io/badge/Microcontroller-ESP32-E7352C?style=for-the-badge" alt="Microcontroller" height="40">
  </a>

  <h3 align="center">Microcontroller</h3>

  <p align="center">
    The Arduino sketch for the ESP32: it reads the sensors, waters the plants, publishes readings and exposes a small HTTP server.
    <br />
    <a href="#the-main-loop"><strong>Explore the docs »</strong></a>
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
      <a href="#usage">Usage</a>
      <ul>
        <li><a href="#hardware">Hardware</a></li>
        <li><a href="#secrets">secrets.h</a></li>
        <li><a href="#libraries">Libraries</a></li>
        <li><a href="#the-main-loop">The Main Loop</a></li>
        <li><a href="#watering-logic">Watering Logic</a></li>
        <li><a href="#pump-modes">Pump Modes</a></li>
        <li><a href="#communication">Communication</a></li>
        <li><a href="#api-device-polling">API Device Polling</a></li>
        <li><a href="#halloween-easter-egg">Halloween Easter Egg</a></li>
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

The Arduino sketch for the ESP32. It reads the sensors, waters the plants, publishes the readings to the API over a WebSocket, reports how much water it used, reads the activation parameters the API decided from it, and exposes a small HTTP server so the API can change the pump modes.

Part of [Greenhouse IoT](../README.md). The other components are the [FastAPI service](../api/README.md) and the [Flutter frontend](../frontend/README.md).

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- BUILT WITH -->
### Built With

* [![ESP32][ESP32.com]][ESP32-url]
* [![Arduino][Arduino.cc]][Arduino-url]
* [ArduinoJson](https://arduinojson.org)
* [DHT sensor library](https://github.com/adafruit/DHT-sensor-library)
* [WebSockets by Markus Sattler](https://github.com/Links2004/arduinoWebSockets)

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- GETTING STARTED -->
## Getting Started

To get the firmware running, follow these steps.

### Prerequisites

* An ESP32 DevKit
* [Arduino IDE](https://www.arduino.cc/en/software) with ESP32 board support
* The libraries listed under [Libraries](#libraries)
* A reachable API — see the [API doc](../api/README.md)

### Installation

1. Create `microcontroller/secrets.h` with your local credentials:

   ```cpp
   #define SSID "your-wifi"
   #define PASSWORD "your-wifi-password"
   #define WS_SERVER_URL "your-api-host"
   #define WS_SERVER_PORT 443
   #define WS_PATH "/mc-ws/"
   #define API_SERVER_URL "https://your-api-host"
   #define PUMP_HISTORY_PATH "/pump/history/"
   ```

   `WS_PATH` needs the trailing slash — the API does not redirect WebSocket requests. `PUMP_PARAMETERS_PATH` defaults to `/pump/parameters/` and only has to be defined to override it.

2. Install the libraries below in the Arduino IDE.

3. Open `microcontroller/microcontroller.ino` and upload it to the board.

4. Set `DEVICE_URL` on the API to the ESP32's address if the API should poll and push the pump modes — see [API device polling](#api-device-polling).

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- USAGE -->
## Usage

### Hardware

An ESP32 DevKit with three sensors per zone:

|         Peripheral         |    Pins    |               Notes               |
|----------------------------|------------|-----------------------------------|
| DHT11 temperature/humidity | 4, 16, 17  | One per zone                      |
| Capacitive soil moisture   | 36, 39, 34 | ADC, raw 0–2800 mapped to 0–100 % |
| Water pump                 | 25, 26, 27 | Digital output                    |

Zone 1 is sensor 1 / pump 1, zone 2 is sensor 2 / pump 2, and so on.

No pin is used twice: the pumps sit on the digital outputs 25, 26 and 27, the moisture sensors on the analog inputs 36, 39 and 34, and the DHT11s on 4, 16 and 17.

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- SECRETS -->
<a id="secrets"></a>
### secrets.h

`microcontroller/secrets.h` holds the local credentials. It is git-ignored and must never be committed. Create it with:

```cpp
#define SSID "your-wifi"
#define PASSWORD "your-wifi-password"
#define WS_SERVER_URL "your-api-host"
#define WS_SERVER_PORT 443
#define WS_PATH "/mc-ws/"
#define API_SERVER_URL "https://your-api-host"
#define PUMP_HISTORY_PATH "/pump/history/"
```

`WS_PATH` needs the trailing slash — the API does not redirect WebSocket requests.

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- LIBRARIES -->
### Libraries

|        Library       |                           Used for                           |
|----------------------|--------------------------------------------------------------|
| `WiFi.h`             | Networking                                                   |
| `WebSocketsClient.h` | The WebSocket to the API                                     |
| `WebServer.h`        | The `/mode` HTTP server the API polls                        |
| `ArduinoJson.h`      | Building and parsing the JSON payloads                       |
| `HTTPClient.h`       | Posting the water usage and reading the activation parameters|
| `DHT.h`              | The DHT11 sensors                                            |
| `freertos/*`         | The queue and tasks that keep the HTTP calls off the main loop|

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- THE MAIN LOOP -->
### The Main Loop

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

`setup()` starts the serial port at 115200, seeds the RNG, syncs the clock from `pool.ntp.org`, connects to Wi-Fi, opens the WebSocket, creates the usage queue and its task, starts the HTTP server, initialises the DHT sensors and sets the pin modes.

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- WATERING LOGIC -->
### Watering Logic

`openPump()` runs a pump when the soil is dry enough, when the API let it water, and when enough time has passed since the last activation:

```cpp
void openPump(int pumpId, int moisturePercent, int curMode) {
  ActivationParameters parameters = readParameters(pumpId);

  if (!parameters.active) {
    Serial.printf("Pump %d does not water, the API switched it off\n", pumpId);
    return;
  }
  if (moisturePercent > parameters.moistureThreshold) {
    return;
  }
  if (hasActivated[pumpId] && parameters.intervalMs > 0 &&
      millis() - lastActivationMs[pumpId] < parameters.intervalMs) {
    return;
  }

  hasActivated[pumpId] = true;
  lastActivationMs[pumpId] = millis();
  activatePumpMode(pumpId, pumpPinFor(pumpId), curMode);
}
```

The parameters come from the API, which asks Gemini what every pump should do with the weather and the state of the greenhouse. They are:

| Field                        | Meaning                                            |
|-------------------------------|----------------------------------------------------|
| `active`                     | whether the pump may water at all                  |
| `moisture_threshold`         | the soil moisture the pump waters at, in percent    |
| `activation_interval_minutes`| the minutes the pump waits between two activations  |

The mode is not part of them: the mode still comes over the `/mode` server, the API pushes it when it changes.

Before the API has answered, the sketch waters at **30 %** without a wait, the way it always did, and it keeps the last parameters it read when the API cannot be reached. The greenhouse never stops watering because of an outage.

The pump decision always uses the **real** readings, even when a garbled reading is being published. The greenhouse keeps watering itself during the easter egg.

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- PUMP MODES -->
### Pump Modes

The modes are an enum whose ordinals are the integers stored in the database:

```cpp
enum OperatingMode { FAST, SLOW, DRIP, SPRINKLE };
```

| Mode | Behaviour | Duration | Litres |
|------------|------------------------------------|--------|--------|
| `FAST`     | `digitalWrite(HIGH)`               | 750 ms | 0.0060 |
| `SLOW`     | `analogWrite(pin, 120)` — 47 % PWM | 750 ms | 0.0028 |
| `DRIP`     | 150 ms on, then 2.5 s off          | 150 ms | 0.0012 |
| `SPRINKLE` | Nothing, not implemented           |   —    |  0.0   |

The litre figures come from `PUMP_LITRES_PER_SECOND = 0.008`, scaled by the run time and, for `SLOW`, by the PWM duty cycle.

The current mode of each pump is kept in `curMode1`, `curMode2`, `curMode3`. The ordinals are shared with the API and the app — see the [root README](../README.md#shared-contract).

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- COMMUNICATION -->
### Communication

#### Outbound: Readings over the WebSocket

`publishSensorReading()` builds the payload with ArduinoJson and sends it with `webSocket.sendTXT()`:

```json
{
  "sensor": 1,
  "moisture_level": 42,
  "temperature": 23.5,
  "humidity": 78,
  "garbled": false
}
```

The socket reconnects every 5 seconds. The device never reads from the WebSocket; `webSocketEvent()` only prints what arrives.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

#### Outbound: Water Usage over HTTP

After a pump actually runs, `reportWaterUsage()` puts a report on a FreeRTOS queue. A separate task pops it and posts it, so the HTTP request never blocks the sensor loop:

```json
{ "pump": 1, "liters": 0.0060 }
```

The queue holds 8 entries. A report is dropped with a log line if the queue is full.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

#### Outbound: The Activation Parameters

The `parametersTask` reads what the API decided for every pump every 60 seconds and stores it, so the sensor loop can ask for it without waiting for the network:

```json
[
  {"pump_id": 1, "active": true, "moisture_threshold": 28,
   "activation_interval_minutes": 90, "mode": 1, "mode_liters": 0.0028,
   "reason": "the soil is dry and it stays hot", "updated_at": "..."}
]
```

The request is `GET {API_SERVER_URL}{PUMP_PARAMETERS_PATH}`, with `PUMP_PARAMETERS_PATH` set to `/pump/parameters/` in `secrets.h`. Only the `pump_id`, `active`, `moisture_threshold` and `activation_interval_minutes` fields are read; the rest is for the app.

The parameters are written under a mutex, because the task writes them and the sensor loop reads them. A payload that is not a list, does not parse, or holds a pump outside 1, 2 and 3 is logged and ignored, and the last good parameters stay in place.

A json boolean has to be read with a boolean default. `entry["active"] | 0` always falls through to the default, because ArduinoJson does not treat a boolean as an integer. `entry["active"] | true` is the right way.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

#### Inbound: The `/mode` Server

The ESP32 runs a `WebServer` on port 80 with three handlers:

| Method |  Path   |            Request            |                    Response                    |
|--------|---------|-------------------------------|------------------------------------------------|
|  GET   | `/mode` | —                             | `{"modes":{"1":"FAST","2":"SLOW","3":"DRIP"}}` |
|  POST  | `/mode` | `{"pump": 1, "mode": "DRIP"}` | `{"pump":1,"mode":"DRIP"}`                     |
|  GET   | `/parameters` | —                       | the activation parameters the device works with |

`POST /mode` also accepts form arguments instead of a JSON body. It answers `400` with `{"error":"pump and mode are required"}` when the pump or the mode is missing, and `404` with `{"error":"unknown pump"}` for a pump that is not 1, 2 or 3.

The API can send the same switch over the WebSocket instead: `{"pump": 1, "mode": "DRIP"}` is read in `webSocketEvent()`, the mode is stored and the pump runs in it right away. That works when the ESP32 is behind a NAT and the API cannot reach its HTTP server.

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- API DEVICE POLLING -->
### API Device Polling

The API is the one that drives the modes, not the device. Set `DEVICE_URL` to the ESP32's address to enable it:

```text
DEVICE_URL=http://192.168.1.50
```

The API then polls `GET {DEVICE_URL}/mode` every `DEVICE_POLL_INTERVAL_SECONDS` (5 by default), records what the device reports in `pump_mode.observed_mode`, and pushes the desired mode with `POST {DEVICE_URL}/mode` whenever the two disagree. The ESP32 must be reachable from wherever the API runs.

That is only needed for reconciliation: a mode changed from the app is also sent over the WebSocket at once, so the pump starts immediately even when `DEVICE_URL` is not set, as long as the ESP32 keeps its `/mc-ws/` connection open.

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- HALLOWEEN EASTER EGG -->
### Halloween Easter Egg

`configTime()` syncs the clock, then:

1. `daysUntilHalloween()` counts the days to the 31st of October.
2. `halloweenHaunting()` returns `0` outside the 14-day window, and otherwise ramps linearly from `0` to `1` as the date approaches.
3. `shouldSendGarbledData()` rolls against `haunting * 0.8`, so the chance of a garbled reading reaches 80% on Halloween night.
4. `garbledReading()` invents nonsense: moisture and humidity between 101 and 999, temperature between −50 °C and 150 °C.

A garbled reading is published with `"garbled": true`. The API stores the flag, raises a spooky alert instead of the threshold alerts, and the app shows a "haunted" banner. The pump logic keeps using the real values.

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- ROADMAP -->
## Roadmap

- [x] Three-zone sensor reading and pump control
- [x] Readings over the WebSocket and queued water-usage reports
- [x] Activation parameters fetched from the API
- [x] Halloween easter egg
- [ ] Implement `SPRINKLE` mode — the function is an empty stub today
- [ ] Send humidity as a float that matches the API schema — the API declares it as an int today
- [ ] Configure the WebSocket library for TLS in `wss://` deployments

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
* [Arduino](https://www.arduino.cc)
* [Espressif ESP32](https://www.espressif.com/en/products/socs/esp32)
* [ArduinoJson](https://arduinojson.org)
* [DHT sensor library](https://github.com/adafruit/DHT-sensor-library)
* [WebSockets by Markus Sattler](https://github.com/Links2004/arduinoWebSockets)
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
[ESP32.com]: https://img.shields.io/badge/ESP32-E7352C?style=for-the-badge&logo=espressif&logoColor=white
[ESP32-url]: https://www.espressif.com/en/products/socs/esp32
[Arduino.cc]: https://img.shields.io/badge/Arduino-00979D?style=for-the-badge&logo=arduino&logoColor=white
[Arduino-url]: https://www.arduino.cc
