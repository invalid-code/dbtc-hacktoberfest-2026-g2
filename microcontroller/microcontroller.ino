// ---- Libraries, includes and pin definitions --------------------------------

#include <WiFi.h>
#include <WebSocketsClient.h>
#include <ArduinoJson.h>
#include <freertos/FreeRTOS.h>
#include <freertos/semphr.h>
#include <esp_system.h>
#include <math.h>
#include <time.h>
#include "DHT.h"

#include "secrets.h"

// One DHT11 temperature/humidity sensor per zone.
#define DHTPIN1 4
#define DHTPIN2 16
#define DHTPIN3 17

#define DHTTYPE DHT11

// ---- Sensor and pump objects, constants and state ---------------------------

DHT tempSensor1(DHTPIN1, DHTTYPE);
DHT tempSensor2(DHTPIN2, DHTTYPE);
DHT tempSensor3(DHTPIN3, DHTTYPE);

WebSocketsClient webSocket;

enum OperatingMode {
  FAST,
  SLOW,
  DRIP,
  SPRINKLE
};

// Pump output pins: pump 1 -> 25, pump 2 -> 26, pump 3 -> 27.
const int PUMP1_PIN = 25;
const int PUMP2_PIN = 26;
const int PUMP3_PIN = 27;

// Sensor input pins: zone 1 -> 36, zone 2 -> 39, zone 3 -> 34.
// No pin is used twice: the pumps are on the digital outputs 25, 26 and 27.
const int MOISTURE_PIN_1 = 36;
const int MOISTURE_PIN_2 = 39;
const int MOISTURE_PIN_3 = 34;

// Raw ADC range of the capacitive soil moisture sensors (0-2800), mapped to 0-100 %.
const int MOISTURE4PIN_LOW_VAL = 4000;
const int MOISTURE4PIN_HIGH_VAL = 1000;
const int MOISTURE3PIN_LOW_VAL = 0;
const int MOISTURE3PIN_HIGH_VAL = 2500;

// How long a watering may run before it is stopped even if the soil never
// reaches the threshold, in milliseconds.
const unsigned long WATERING_TIMEOUT_MS = 30000;

// Drip mode: a short burst followed by a longer pause, in milliseconds.
const unsigned long DRIP_ON_MS = 150;
const unsigned long DRIP_OFF_MS = 2500;

// PWM duty cycle (0-255) used by the slow mode.
const int SLOW_PWM = 120;

// Measured pump flow rate, used to work out how much water a run used.
const float PUMP_LITRES_PER_SECOND = 0.008f;

// The Halloween easter egg window: October (tm_mon is zero based) and the 31st.
const int HALLOWEEN_MONTH = 9;
const int HALLOWEEN_DAY = 31;
// Number of days before Halloween on which the haunting starts.
const int HAUNTING_WINDOW_DAYS = 14;
// Highest chance of sending a garbled reading, reached on Halloween night.
const float MAX_GARBLED_CHANCE = 0.8f;

// The mode each pump is currently running.
int curMode1 = FAST;
int curMode2 = FAST;
int curMode3 = FAST;

// ---- The activation parameters the API decides -------------------------------

// The soil moisture a pump waters at until the API says otherwise.
const int DEFAULT_MOISTURE_THRESHOLD = 30;

// What the API decided for one pump.
struct ActivationParameters {
  bool active = true;
  int moistureThreshold = DEFAULT_MOISTURE_THRESHOLD;
  unsigned long intervalMs = 0;
  // false until the API has answered at least once.
  bool known = false;
};

// The parameters of the pumps, indexed by the pump id.
ActivationParameters activationParameters[4];

// When each pump last ran, and whether it ever did.
unsigned long lastActivationMs[4] = {0, 0, 0, 0};
bool hasActivated[4] = {false, false, false, false};

// Guards the parameters: they are written by the socket event and read by the
// sensor loop.
SemaphoreHandle_t parametersMutex = nullptr;

struct GarbledReading {
  int moisture;
  int humidity;
  float temperature;
};

// The watering cycle of one pump. A cycle runs until the soil reaches the
// threshold, the API switches the pump off, or the safety timeout expires.
struct PumpCycle {
  bool running = false;
  int mode = FAST;
  unsigned long startedMs = 0;
  unsigned long toggledMs = 0;
  unsigned long onStartedMs = 0;
  unsigned long onMs = 0;
  bool outputOn = false;
};

// Indexed by pump id; slot 0 is unused.
PumpCycle pumpCycles[4] = {};

// Mode changes that arrived over the socket, run by the main loop so the
// socket callback never blocks on a watering.
bool pumpActivationPending[4] = {false, false, false, false};
int pendingPumpMode[4] = {FAST, FAST, FAST, FAST};

// ---- Mode helpers ----------------------------------------------------------

// The device speaks mode names over the socket, while the database stores ordinals.
const char* modeName(int mode) {
  switch (mode) {
    case SLOW:
      return "SLOW";
    case DRIP:
      return "DRIP";
    case SPRINKLE:
      return "SPRINKLE";
    default:
      return "FAST";
  }
}

// Inverse of modeName(): turns a mode name back into its ordinal.
int modeFromName(const String& name) {
  if (name.equalsIgnoreCase("SLOW")) return SLOW;
  if (name.equalsIgnoreCase("DRIP")) return DRIP;
  if (name.equalsIgnoreCase("SPRINKLE")) return SPRINKLE;
  return FAST;
}

// Returns the pointer to the current mode of a pump, or null for an unknown pump.
int* modeSlotFor(int pumpId) {
  switch (pumpId) {
    case 1:
      return &curMode1;
    case 2:
      return &curMode2;
    case 3:
      return &curMode3;
  }
  return nullptr;
}

// The output pin of a pump.
int pumpPinFor(int pumpId) {
  switch (pumpId) {
    case 1:
      return PUMP1_PIN;
    case 2:
      return PUMP2_PIN;
    case 3:
      return PUMP3_PIN;
  }
  return -1;
}

// How much water a run used, from the time the output was on and the flow of
// the mode. The slow mode's PWM scales the flow down; drip already counts only
// the time the pump was on.
float pumpLitres(int mode, unsigned long onMs) {
  float litres = PUMP_LITRES_PER_SECOND * (onMs / 1000.0f);
  if (mode == SLOW) {
    litres *= SLOW_PWM / 255.0f;
  }
  return litres;
}

// ---- WebSocket event handling -----------------------------------------------

// Tells the API which mode a pump is running, so it can record what it observed.
void sendModeApplied(int pumpId, int mode) {
  String json = "{\"type\":\"mode_applied\",\"pump\":" + String(pumpId) +
                ",\"mode\":\"" + String(modeName(mode)) + "\"}";
  webSocket.sendTXT(json);
}

// Applies a mode that came over the socket. A live command also schedules a
// watering, the modes sent on connect only bring the device in step.
bool applyPumpMode(int pumpId, int mode, bool runPump) {
  int* slot = modeSlotFor(pumpId);
  if (slot == nullptr) {
    return false;
  }

  bool changed = (*slot != mode);
  *slot = mode;
  sendModeApplied(pumpId, mode);

  if (changed) {
    Serial.printf("Pump %d switched to %s over the socket\n", pumpId,
                  modeName(mode));
  }

  if (runPump) {
    pumpActivationPending[pumpId] = true;
    pendingPumpMode[pumpId] = mode;
  }
  return changed;
}

// Callback for the socket library; everything the device knows arrives here.
void webSocketEvent(WStype_t type, uint8_t* payload, size_t length) {
  switch (type) {
    case WStype_DISCONNECTED:
      Serial.println("Disconnected!");
      break;

    case WStype_CONNECTED:
      Serial.printf("Connected to url: %s\n", payload);
      break;

    case WStype_TEXT: {
      JsonDocument doc;
      if (deserializeJson(doc, payload, length)) {
        Serial.printf("Could not parse: %s\n", payload);
        break;
      }

      String messageType = doc["type"] | "";

      if (messageType == "modes") {
        JsonObject modes = doc["modes"].as<JsonObject>();
        for (JsonPair entry : modes) {
          int pumpId = String(entry.key().c_str()).toInt();
          const char* name = entry.value().as<const char*>();
          if (pumpId >= 1 && pumpId <= 3 && name != nullptr) {
            applyPumpMode(pumpId, modeFromName(String(name)), false);
          }
        }
        break;
      }

      if (messageType == "mode") {
        int pumpId = doc["pump"] | 0;
        const char* requestedMode = doc["mode"] | "";
        if (pumpId >= 1 && pumpId <= 3 && requestedMode[0] != '\0') {
          applyPumpMode(pumpId, modeFromName(String(requestedMode)), true);
        }
        break;
      }

      if (messageType == "parameters") {
        applyActivationParameters(doc["parameters"].as<JsonArray>());
        break;
      }

      Serial.printf("Received: %s\n", payload);
      break;
    }

    case WStype_BIN:
    case WStype_ERROR:
    case WStype_FRAGMENT_TEXT_START:
    case WStype_FRAGMENT_BIN_START:
    case WStype_FRAGMENT:
    case WStype_PING:
    case WStype_PONG:
      break;
  }
}

// ---- The activation parameters ------------------------------------------------

// Applies the activation parameters the API sends over the socket. The last
// ones are kept until the API sends new ones, so the greenhouse keeps watering
// itself the way it did before.
void applyActivationParameters(JsonArray pumps) {
  if (pumps.isNull()) {
    return;
  }

  for (size_t i = 0; i < pumps.size(); i++) {
    JsonObject entry = pumps[i].as<JsonObject>();
    int pumpId = entry["pump_id"] | 0;
    if (pumpId < 1 || pumpId > 3) {
      continue;
    }

    int intervalMinutes = entry["activation_interval_minutes"] | 0;
    ActivationParameters parameters;
    // a json boolean has to be read with a boolean default, an integer default
    // would always fall through to the default
    parameters.active = entry["active"] | true;
    parameters.moistureThreshold =
        entry["moisture_threshold"] | DEFAULT_MOISTURE_THRESHOLD;
    parameters.intervalMs =
        intervalMinutes > 0 ? (unsigned long)intervalMinutes * 60000UL : 0UL;
    parameters.known = true;

    if (parametersMutex != nullptr) {
      xSemaphoreTake(parametersMutex, portMAX_DELAY);
    }
    activationParameters[pumpId] = parameters;
    if (parametersMutex != nullptr) {
      xSemaphoreGive(parametersMutex);
    }

    Serial.printf("Pump %d is %s, it waters at %d %% soil moisture, every %d minutes\n",
                  pumpId, parameters.active ? "active" : "switched off",
                  parameters.moistureThreshold, intervalMinutes);
  }
}

// The parameters of a pump, as the API last left them.
ActivationParameters readParameters(int pumpId) {
  ActivationParameters parameters;
  if (parametersMutex != nullptr) {
    xSemaphoreTake(parametersMutex, portMAX_DELAY);
  }
  if (pumpId >= 1 && pumpId <= 3) {
    parameters = activationParameters[pumpId];
  }
  if (parametersMutex != nullptr) {
    xSemaphoreGive(parametersMutex);
  }
  return parameters;
}

// ---- Water usage reporting --------------------------------------------------

// Sends the water usage to the API over the socket.
void reportWaterUsage(int pumpId, float litres) {
  char litresStr[16];
  snprintf(litresStr, sizeof(litresStr), "%.4f", litres);
  String json = "{\"type\":\"water_usage\",\"pump\":" + String(pumpId) +
                ",\"liters\":" + String(litresStr) + "}";

  if (webSocket.sendTXT(json)) {
    Serial.printf("Reported %.4f litres for pump %d\n", litres, pumpId);
  } else {
    Serial.println("Could not report the pump water usage over the socket");
  }
}

// ---- Pump actuation ---------------------------------------------------------

void stopPumpCycle(int pumpId, const char* reason);

// Drives the output of a pump for the mode of its running cycle.
void writePumpOutput(int pumpId, bool on) {
  int pumpPin = pumpPinFor(pumpId);
  if (pumpPin < 0) {
    return;
  }

  if (pumpCycles[pumpId].mode == SLOW) {
    analogWrite(pumpPin, on ? SLOW_PWM : 0);
  } else {
    digitalWrite(pumpPin, on ? HIGH : LOW);
  }
}

// Starts a watering cycle and leaves the pump on until the soil reaches the
// threshold, the API switches it off, or the safety timeout expires.
bool startPumpCycle(int pumpId, int mode) {
  if (pumpId < 1 || pumpId > 3) {
    return false;
  }
  if (pumpCycles[pumpId].running) {
    stopPumpCycle(pumpId, "a new mode was applied");
  }
  if (mode == SPRINKLE) {
    Serial.printf("Pump %d has no SPRINKLE behavior, not watering\n", pumpId);
    return false;
  }

  unsigned long now = millis();
  PumpCycle& cycle = pumpCycles[pumpId];
  cycle.running = true;
  cycle.mode = mode;
  cycle.startedMs = now;
  cycle.toggledMs = now;
  cycle.onStartedMs = now;
  cycle.onMs = 0;
  cycle.outputOn = true;
  writePumpOutput(pumpId, true);

  hasActivated[pumpId] = true;
  lastActivationMs[pumpId] = now;
  Serial.printf("Pump %d starts watering in %s mode\n", pumpId, modeName(mode));
  return true;
}

// Stops a watering cycle, reports the water that actually flowed and leaves the
// pump ready for the next interval.
void stopPumpCycle(int pumpId, const char* reason) {
  PumpCycle& cycle = pumpCycles[pumpId];
  if (!cycle.running) {
    return;
  }

  unsigned long now = millis();
  if (cycle.outputOn) {
    cycle.onMs += now - cycle.onStartedMs;
  }
  writePumpOutput(pumpId, false);

  cycle.running = false;
  cycle.outputOn = false;

  float litres = pumpLitres(cycle.mode, cycle.onMs);
  Serial.printf("Pump %d stops watering (%s), %.4f litres in %lu ms\n", pumpId,
                reason, litres, cycle.onMs);
  reportWaterUsage(pumpId, litres);
}

// Drives the drip pulses and the stop conditions of every running pump. Called
// from the main loop, so the socket and the sensor cycle stay responsive.
void servicePumpCycles() {
  unsigned long now = millis();

  for (int pumpId = 1; pumpId <= 3; pumpId++) {
    PumpCycle& cycle = pumpCycles[pumpId];
    if (!cycle.running) {
      continue;
    }

    ActivationParameters parameters = readParameters(pumpId);
    if (!parameters.active) {
      stopPumpCycle(pumpId, "the API switched it off");
      continue;
    }

    if (now - cycle.startedMs >= WATERING_TIMEOUT_MS) {
      stopPumpCycle(pumpId, "the safety timeout was reached");
      continue;
    }

    if (cycle.mode == DRIP) {
      unsigned long elapsed = now - cycle.toggledMs;
      if (cycle.outputOn && elapsed >= DRIP_ON_MS) {
        cycle.onMs += elapsed;
        writePumpOutput(pumpId, false);
        cycle.outputOn = false;
        cycle.toggledMs = now;
      } else if (!cycle.outputOn && elapsed >= DRIP_OFF_MS) {
        cycle.onStartedMs = now;
        writePumpOutput(pumpId, true);
        cycle.outputOn = true;
        cycle.toggledMs = now;
      }
    }
  }
}

// ---- Sensor publishing ------------------------------------------------------

// Builds and sends the reading payload over the WebSocket.
void sendSensorData(int sensor, int moisturePercent, float tempSensorValue, float humiditySensorValue, bool garbled) {
  if (WiFi.status() == WL_CONNECTED) {
    JsonDocument doc;
    doc["sensor"] = sensor;
    doc["moisture_level"] = moisturePercent;
    doc["temperature"] = tempSensorValue;
    doc["humidity"] = humiditySensorValue;
    doc["garbled"] = garbled;

    String jsonString;
    serializeJson(doc, jsonString);
    webSocket.sendTXT(jsonString);
    if (garbled) {
      Serial.println("Sent a haunted sensor data payload");
    } else {
      Serial.println("Sent sensor data payload");
    }
  }
}

// ---- The Halloween easter egg -----------------------------------------------

// The days left until the 31st of October.
int daysUntilHalloween() {
  time_t now = 0;
  time(&now);

  struct tm nowInfo;
  localtime_r(&now, &nowInfo);

  struct tm today = nowInfo;
  today.tm_hour = 0;
  today.tm_min = 0;
  today.tm_sec = 0;

  struct tm halloween = {};
  halloween.tm_year = nowInfo.tm_year;
  halloween.tm_mon = HALLOWEEN_MONTH;
  halloween.tm_mday = HALLOWEEN_DAY;
  halloween.tm_isdst = -1;

  double days = difftime(mktime(&halloween), mktime(&today)) / 86400.0;
  return (int)round(days);
}

// 0 outside the 14 day window, otherwise a ramp from 0 to 1 towards Halloween.
float halloweenHaunting() {
  int days = daysUntilHalloween();
  if (days < 0 || days > HAUNTING_WINDOW_DAYS) {
    return 0.0f;
  }
  return (float)(HAUNTING_WINDOW_DAYS - days) / (float)HAUNTING_WINDOW_DAYS;
}

// Rolls against the haunting level, so the chance reaches 80% on Halloween night.
bool shouldSendGarbledData() {
  float haunting = halloweenHaunting();
  if (haunting <= 0.0f) {
    return false;
  }
  uint32_t roll = esp_random() % 1000;
  return roll < (uint32_t)(haunting * MAX_GARBLED_CHANCE * 1000.0f);
}

// Invents nonsense values for a haunted reading.
GarbledReading garbledReading() {
  GarbledReading reading;
  reading.moisture = (int)random(101, 1000);
  reading.humidity = (int)random(101, 1000);
  reading.temperature = -50.0f + ((float)random(0, 2000) / 10.0f);
  return reading;
}

// Publishes either the real reading or a garbled one.
void publishSensorReading(int sensor, int moisturePercent, float tempValue, float humidityValue) {
  if (shouldSendGarbledData()) {
    GarbledReading haunted = garbledReading();
    Serial.printf("The sensors are haunted, sending garbled data for sensor %d\n", sensor);
    sendSensorData(sensor, haunted.moisture, haunted.temperature, haunted.humidity, true);
    return;
  }
  sendSensorData(sensor, moisturePercent, tempValue, humidityValue, false);
}

// Keeps a running pump watering until the soil reaches the threshold, or
// starts one when the soil is dry enough, the API let the pump water, and
// enough time has passed since the last activation. Before the API has
// answered the pump waters at 30 % without a wait, the way it always did.
void updatePump(int pumpId, int moisturePercent, int curMode) {
  ActivationParameters parameters = readParameters(pumpId);

  if (pumpCycles[pumpId].running) {
    if (moisturePercent >= parameters.moistureThreshold) {
      stopPumpCycle(pumpId, "the soil reached the threshold");
    }
    return;
  }

  if (curMode == SPRINKLE) {
    return;
  }

  if (!parameters.active) {
    Serial.printf("Pump %d does not water, the API switched it off\n", pumpId);
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

// ---- Setup and the main loop ------------------------------------------------

// Connects to Wi-Fi and the socket and initialises the sensors.
void setup() {
  Serial.begin(115200);

  srandom(esp_random());
  configTime(0, 0, "pool.ntp.org");

  WiFi.begin(SSID, PASSWORD);
  Serial.println("Connecting");
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("");
  Serial.print("Connected to WiFi network with IP Address: ");
  Serial.println(WiFi.localIP());

  // The path needs its trailing slash: the API does not redirect WebSocket requests.
  // Render serves wss:// on 443, so the TLS variant is required here.
  webSocket.beginSSL(WS_SERVER_URL, WS_SERVER_PORT, WS_PATH);
  webSocket.onEvent(webSocketEvent);
  webSocket.setReconnectInterval(5000);

  parametersMutex = xSemaphoreCreateMutex();
  if (parametersMutex == nullptr) {
    Serial.println("Could not create the pump parameters lock");
  }

  tempSensor1.begin();
  tempSensor2.begin();
  tempSensor3.begin();


  pinMode(PUMP1_PIN, OUTPUT);
  pinMode(PUMP2_PIN, OUTPUT);
  pinMode(PUMP3_PIN, OUTPUT);

  pinMode(MOISTURE_PIN_1, INPUT);
  pinMode(MOISTURE_PIN_2, INPUT);
  pinMode(MOISTURE_PIN_3, INPUT);

  Serial.println("ESP32 Watering System Initialized");
}

// Services the socket, drives the running pumps, and every 10 seconds reads
// each zone, publishes the reading and decides whether to water.
void loop() {
  webSocket.loop();

  // The pumps are driven here instead of in the socket callback, so the
  // watering keeps going while the socket is busy.
  servicePumpCycles();

  // A mode change that arrived over the socket starts a watering here, outside
  // the socket callback.
  for (int pumpId = 1; pumpId <= 3; pumpId++) {
    if (pumpActivationPending[pumpId]) {
      pumpActivationPending[pumpId] = false;
      startPumpCycle(pumpId, pendingPumpMode[pumpId]);
    }
  }

  if (WiFi.status() != WL_CONNECTED) {
    static unsigned long lastWifiAttempt = 0;
    if (millis() - lastWifiAttempt >= 5000) {
      lastWifiAttempt = millis();
      Serial.println("Wi-Fi disconnected. Reconnecting...");
      WiFi.begin(SSID, PASSWORD);
    }
  }

  static unsigned long lastSent = 0;
  if (millis() - lastSent > 10000) {
    lastSent = millis();

    // The pump decision always uses the real readings, even while a garbled
    // reading is being published, so the greenhouse keeps watering itself.
    int moisture1Value = analogRead(MOISTURE_PIN_1);
    int moisture1Percent = map(moisture1Value, MOISTURE3PIN_LOW_VAL, MOISTURE3PIN_HIGH_VAL, 0, 100);
    moisture1Percent = constrain(moisture1Percent, 0, 100);
    Serial.print("Soil moisture 1 raw: ");
    Serial.println(moisture1Value);
    Serial.print("Soil moisture 1 percentage: ");
    Serial.println(moisture1Percent);


    float tempSensor1Value = tempSensor1.readTemperature();
    Serial.print("Temperature 1 raw: ");
    Serial.println(tempSensor1Value);

    float humiditySensor1Value = tempSensor1.readHumidity();
    Serial.print("Humidity 1 raw: ");
    Serial.println(humiditySensor1Value);

    publishSensorReading(1, moisture1Percent, tempSensor1Value, humiditySensor1Value);
    updatePump(1, moisture1Percent, curMode1);

    int moisture2Value = analogRead(MOISTURE_PIN_2);
    int moisture2Percent = map(moisture2Value, MOISTURE4PIN_LOW_VAL, MOISTURE4PIN_HIGH_VAL, 0, 100);
    moisture2Percent = constrain(moisture2Percent, 0, 100);
    Serial.print("Soil moisture 2 raw: ");
    Serial.println(moisture2Value);
    Serial.print("Soil moisture 2 percentage: ");
    Serial.println(moisture2Percent);

    float tempSensor2Value = tempSensor2.readTemperature();
    Serial.print("Temperature 2 raw: ");
    Serial.println(tempSensor2Value);

    float humiditySensor2Value = tempSensor2.readHumidity();
    Serial.print("Humidity 2 raw: ");
    Serial.println(humiditySensor2Value);

    publishSensorReading(2, moisture2Percent, tempSensor2Value, humiditySensor2Value);
    updatePump(2, moisture2Percent, curMode2);

    int moisture3Value = analogRead(MOISTURE_PIN_3);
    int moisture3Percent = map(moisture3Value, MOISTURE4PIN_LOW_VAL, MOISTURE4PIN_HIGH_VAL, 0, 100);
    moisture3Percent = constrain(moisture3Percent, 0, 100);
    Serial.print("Soil moisture 3 raw: ");
    Serial.println(moisture3Value);
    Serial.print("Soil moisture 3 percentage: ");
    Serial.println(moisture3Percent);

    float tempSensor3Value = tempSensor3.readTemperature();
    Serial.print("Temperature 3 raw: ");
    Serial.println(tempSensor3Value);

    float humiditySensor3Value = tempSensor3.readHumidity();
    Serial.print("Humidity 3 raw: ");
    Serial.println(humiditySensor3Value);

    publishSensorReading(3, moisture3Percent, tempSensor3Value, humiditySensor3Value);
    updatePump(3, moisture3Percent, curMode3);
  }
}