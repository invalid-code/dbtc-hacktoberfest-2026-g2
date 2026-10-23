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

The Arduino sketch for the ESP32. It reads the sensors, waters the plants, publishes the readings and the water it used to the API over a WebSocket, and receives the pump modes and activation parameters over the same socket. It runs no server of its own and makes no HTTP requests.

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
   ```

   `WS_PATH` needs the trailing slash — the API does not redirect WebSocket requests.

2. Install the libraries below in the Arduino IDE.

3. Open `microcontroller/microcontroller.ino` and upload it to the board. The device connects out to the API and needs no address of its own.

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
```

`WS_PATH` needs the trailing slash — the API does not redirect WebSocket requests.

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- LIBRARIES -->
### Libraries

|        Library       |                           Used for                           |
|----------------------|--------------------------------------------------------------|
| `WiFi.h`             | Networking                                                   |
| `WebSocketsClient.h` | The only channel to the API                                  |
| `ArduinoJson.h`      | Building and parsing the JSON payloads                       |
| `DHT.h`              | The DHT11 sensors                                            |
| `freertos/*`         | The mutex guarding the activation parameters                 |

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- THE MAIN LOOP -->
### The Main Loop

`loop()` runs continuously and does four things:

1. `webSocket.loop()` — keeps the socket alive, pumps its reconnect timer and
   receives the modes and parameters.
2. `servicePumpCycles()` — drives the drip pulses and stops a pump when its
   safety timeout expires or the API switches it off.
3. Starts a watering when a mode command asked for it.
4. Every 10 seconds, reads each zone, publishes it and updates its pump.

Each 10-second cycle, for each of the three zones:

```cpp
int moistureValue = analogRead(MOISTURE_PIN_1);
int moisturePercent = map(moistureValue, MOISTURE3PIN_LOW_VAL, MOISTURE3PIN_HIGH_VAL, 0, 100);
moisturePercent = constrain(moisturePercent, 0, 100);

float temp = tempSensor1.readTemperature();
float humidity = tempSensor1.readHumidity();

publishSensorReading(1, moisturePercent, temp, humidity);
updatePump(1, moisturePercent, curMode1);
```

The loop retries Wi-Fi every 5 seconds without blocking, so the pumps and the
sensor cycle keep running while the connection comes back.

`setup()` starts the serial port at 115200, seeds the RNG, syncs the clock from `pool.ntp.org`, connects to Wi-Fi, opens the WebSocket, creates the parameters mutex, initialises the DHT sensors and sets the pin modes.

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- WATERING LOGIC -->
### Watering Logic

`updatePump()` starts a watering when the soil is dry enough, when the API let
the pump water, and when enough time has passed since the last activation. The
pump then stays on until the soil reaches `moisture_threshold`, the API switches
the pump off, or the 30-second safety timeout expires:

```cpp
void updatePump(int pumpId, int moisturePercent, int curMode) {
  ActivationParameters parameters = readParameters(pumpId);

  if (pumpCycles[pumpId].running) {
    if (moisturePercent >= parameters.moistureThreshold) {
      stopPumpCycle(pumpId, "the soil reached the threshold");
    }
    return;
  }

  if (curMode == SPRINKLE || !parameters.active) {
    return;
  }
  if (moisturePercent >= parameters.moistureThreshold) {
    return;
  }
  if (hasActivated[pumpId] && parameters.intervalMs > 0 &&
      millis() - lastActivationMs[pumpId] < parameters.intervalMs) {
    return;
  }

  startPumpCycle(pumpId, curMode);
}
```

`startPumpCycle()` turns the output on, `servicePumpCycles()` handles the drip
pulses and timeout, and `stopPumpCycle()` reports the litres actually delivered
from the time the output was on and the mode's flow.

The parameters come from the API, which asks Gemini what every pump should do with the weather and the state of the greenhouse. They are:

| Field                        | Meaning                                            |
|-------------------------------|----------------------------------------------------|
| `active`                     | whether the pump may water at all                  |
| `moisture_threshold`         | the target soil moisture, in percent; the pump waters below it and stops when it reaches it |
| `activation_interval_minutes`| the minutes the pump waits between two activations  |

The mode is not part of them: it arrives separately as a `mode` command over the socket, and the API sends it when it changes.

Before the API has answered, the sketch waters at **30 %** without a wait, the way it always did, and it keeps the last parameters it received when the socket cannot be reached. The greenhouse never stops watering because of an outage.

The pump decision always uses the **real** readings, even when a garbled reading is being published. The greenhouse keeps watering itself during the easter egg.

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- PUMP MODES -->
### Pump Modes

The modes are an enum whose ordinals are the integers stored in the database:

```cpp
enum OperatingMode { FAST, SLOW, DRIP, SPRINKLE };
```

| Mode | Behaviour | Average flow |
|------------|------------------------------------|--------------|
| `FAST`     | `digitalWrite(HIGH)`               | 0.0080 L/s   |
| `SLOW`     | `analogWrite(pin, 120)` — 47 % PWM | 0.0038 L/s   |
| `DRIP`     | 150 ms on, then 2.5 s off          | 0.00045 L/s  |
| `SPRINKLE` | Nothing, not implemented           | 0.0 L/s      |

A watering does not have a fixed duration: it runs until the soil reaches the
threshold, up to the 30-second safety timeout. The flow figures come from
`PUMP_LITRES_PER_SECOND = 0.008`, scaled by the PWM duty cycle or the drip
on/off ratio, and the reported usage is the actual time the output was on.

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

The socket reconnects every 5 seconds. The API broadcasts the stored readings back to every socket; the device logs those and ignores them, and `webSocketEvent()` handles the commands that follow.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

#### Outbound: Water Usage over the WebSocket

After a pump stops, `reportWaterUsage()` sends the litres it actually delivered
over the socket:

```json
{ "type": "water_usage", "pump": 1, "liters": 0.0216 }
```

Every pump run happens in the main loop — the sensor cycle or a pending mode
command — so the socket callback never blocks on a watering. The amount varies
with how long the soil takes to reach the threshold, up to the safety timeout.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

#### Inbound: Modes and Parameters

On connect the API sends the modes it wants every pump to run. They are applied without watering, so a reconnect does not give the plants a drink:

```json
{ "type": "modes", "modes": { "1": "FAST", "2": "SLOW", "3": "DRIP" } }
```

A mode change from the app arrives as a live command. The mode is stored, the device answers with `mode_applied`, and a watering is scheduled for the main loop. A live command always starts a watering, even when it names the mode the pump is already in, so the same button gives the plants another drink after the soil has reached the threshold. The modes sent on connect never water.

```json
{ "type": "mode", "pump": 1, "mode": "DRIP" }
```

```json
{ "type": "mode_applied", "pump": 1, "mode": "DRIP" }
```

The activation parameters arrive on connect and again whenever the weather service changes them:

```json
{
  "type": "parameters",
  "parameters": [
    {"pump_id": 1, "active": true, "moisture_threshold": 28,
     "activation_interval_minutes": 90}
  ]
}
```

Only the `pump_id`, `active`, `moisture_threshold` and `activation_interval_minutes` fields are read. The parameters are written under a mutex, because the socket callback writes them and the sensor loop reads them. A payload that does not parse, or holds a pump outside 1, 2 and 3, is logged and ignored, and the last good parameters stay in place.

A json boolean has to be read with a boolean default. `entry["active"] | 0` always falls through to the default, because ArduinoJson does not treat a boolean as an integer. `entry["active"] | true` is the right way.

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
- [x] Readings and water usage over the WebSocket
- [x] Activation parameters received over the WebSocket
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
