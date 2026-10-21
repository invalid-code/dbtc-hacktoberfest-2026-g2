// TODO need to know how much water was used and send the data to the backend

// ---- Libraries, includes and pin definitions --------------------------------

#include <WiFi.h>
#include <WebSocketsClient.h>
#include <WebServer.h>
#include <ArduinoJson.h>
#include <HTTPClient.h>
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>
#include <freertos/queue.h>
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
WebServer deviceServer(80);

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

// Sensor input pins: zone 1 -> moisture 36 / water level 39,
// zone 2 -> moisture 35 / water level 32, zone 3 -> moisture 25 / water level 26.
// Note that pins 25 and 26 are used both as a pump output and as an analog input
// for zone 3.
const int MOISTURE_PIN_1 = 36;
const int WATER_LEVEL_PIN_1 = 39;
const int MOISTURE_PIN_2 = 35;
const int WATER_LEVEL_PIN_2 = 32;
const int MOISTURE_PIN_3 = 25;
const int WATER_LEVEL_PIN_3 = 26;

// Raw ADC range of the capacitive soil moisture sensors (0-2800), mapped to 0-100 %.
const int MOISTURE_LOW_VAL = 0;
const int MOISTURE_HIGH_VAL = 2800;
// Raw ADC range of the water level sensors (0-1400). These sensors are declared
// and pin-moded but never read.
const int WATER_LEVEL_LOW_VAL = 0;
const int WATER_LEVEL_HIGH_VAL = 1400;

// How long each mode runs the pump, in milliseconds.
const int FAST_RUN_MS = 750;
const int SLOW_RUN_MS = 750;
const int DRIP_RUN_MS = 150;

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

struct UsageReport {
  int pumpId;
  float litres;
};

struct GarbledReading {
  int moisture;
  int humidity;
  float temperature;
};

// Queue of pending water usage reports, drained by the usage reporter task.
QueueHandle_t usageQueue = nullptr;

// ---- Mode helpers ----------------------------------------------------------

// The device speaks mode names over HTTP, while the database stores ordinals.
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

// How much water a run in each mode uses, from the flow rate and the timings.
float modeLitres(int mode) {
  switch (mode) {
    case FAST:
      return PUMP_LITRES_PER_SECOND * (FAST_RUN_MS / 1000.0f);
    case SLOW:
      return PUMP_LITRES_PER_SECOND * (SLOW_RUN_MS / 1000.0f) *
             (SLOW_PWM / 255.0f);
    case DRIP:
      return PUMP_LITRES_PER_SECOND * (DRIP_RUN_MS / 1000.0f);
    case SPRINKLE:
      return 0.0f;
  }
  return 0.0f;
}

// ---- WebSocket event handling -----------------------------------------------

// Callback for the socket library; the device only prints what arrives, it never
// reads from the socket.
void webSocketEvent(WStype_t type, uint8_t* payload, size_t length) {
  switch (type) {
    case WStype_DISCONNECTED:
      Serial.println("Disconnected!");
      break;

    case WStype_CONNECTED:
      Serial.printf("Connected to url: %s\n", payload);
      break;

    case WStype_TEXT:
      Serial.printf("Received: %s\n", payload);
      break;

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

// ---- The device HTTP server (/mode handlers) ---------------------------------

// The API polls this to learn which mode each pump is running.
void handleGetMode() {
  String json = "{\"modes\":{";
  json += "\"1\":\"" + String(modeName(curMode1)) + "\",";
  json += "\"2\":\"" + String(modeName(curMode2)) + "\",";
  json += "\"3\":\"" + String(modeName(curMode3)) + "\"";
  json += "}}";
  deviceServer.send(200, "application/json", json);
}

// The API pushes the desired mode here; it accepts a JSON body or form arguments.
void handlePostMode() {
  int pumpId = 0;
  int mode = FAST;
  bool parsed = false;

  String body = deviceServer.arg("plain");
  if (body.length() > 0) {
    JsonDocument doc;
    if (!deserializeJson(doc, body.c_str())) {
      pumpId = doc["pump"] | 0;
      const char* requested = doc["mode"] | "FAST";
      mode = modeFromName(String(requested));
      parsed = true;
    }
  }

  if (!parsed) {
    if (!deviceServer.hasArg("pump") || !deviceServer.hasArg("mode")) {
      deviceServer.send(
          400, "application/json", "{\"error\":\"pump and mode are required\"}");
      return;
    }
    pumpId = deviceServer.arg("pump").toInt();
    mode = modeFromName(deviceServer.arg("mode"));
  }

  int* slot = modeSlotFor(pumpId);
  if (slot == nullptr) {
    deviceServer.send(404, "application/json", "{\"error\":\"unknown pump\"}");
    return;
  }

  *slot = mode;
  Serial.printf("Pump %d switched to %s\n", pumpId, modeName(mode));

  String json = "{\"pump\":" + String(pumpId) + ",\"mode\":\"" +
                String(modeName(mode)) + "\"}";
  deviceServer.send(200, "application/json", json);
}

// ---- Water usage reporting --------------------------------------------------

// Posts the water usage to the API.
void sendPumpWaterUsage(int pumpId, float litres) {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("Skipping pump water usage, wifi is down");
    return;
  }

  HTTPClient http;
  String url = String(API_SERVER_URL) + String(PUMP_HISTORY_PATH);
  if (!http.begin(url)) {
    Serial.println("Could not start the pump history request");
    return;
  }
  http.addHeader("Content-Type", "application/json");

  char litresStr[16];
  snprintf(litresStr, sizeof(litresStr), "%.4f", litres);
  String body =
      "{\"pump\":" + String(pumpId) + ",\"liters\":" + String(litresStr) + "}";

  int status = http.POST(body);
  if (status >= 200 && status < 300) {
    Serial.printf("Reported %.4f litres for pump %d\n", litres, pumpId);
  } else {
    Serial.printf("Pump history request failed (%d): %s\n", status,
                  http.getString().c_str());
  }
  http.end();
}

// Puts the report on the queue so the HTTP call never blocks the sensor loop.
void reportWaterUsage(int pumpId, float litres) {
  if (usageQueue == nullptr) {
    return;
  }
  UsageReport report = {pumpId, litres};
  if (xQueueSend(usageQueue, &report, 0) != pdTRUE) {
    Serial.println("Dropped a pump water usage report, queue is full");
  }
}

// The task that drains the queue and does the actual POST.
void usageReporterTask(void* arg) {
  (void)arg;
  for (;;) {
    UsageReport report;
    if (xQueueReceive(usageQueue, &report, portMAX_DELAY) == pdTRUE) {
      sendPumpWaterUsage(report.pumpId, report.litres);
    }
  }
}

// ---- Pump actuation ---------------------------------------------------------

// Fast mode: full power for FAST_RUN_MS.
void fast(int pumpPin) {
  Serial.println("-- Fast Flow Mode --");
  digitalWrite(pumpPin, HIGH);
  delay(FAST_RUN_MS);
  digitalWrite(pumpPin, LOW);
}

// Slow mode: reduced power (SLOW_PWM) for SLOW_RUN_MS.
void slow(int pumpPin) {
  Serial.println("-- Slow Flow Mode --");
  analogWrite(pumpPin, SLOW_PWM);
  delay(SLOW_RUN_MS);
  analogWrite(pumpPin, 0);
}

// Drip mode: a short DRIP_RUN_MS burst followed by a pause.
void drip(int pumpPin) {
  Serial.println("-- Drip Flow Mode --");
  digitalWrite(pumpPin, HIGH);
  delay(DRIP_RUN_MS);

  digitalWrite(pumpPin, LOW);
  delay(2500);
}

// Sprinkle mode: not implemented, so the pump never actually runs here.
void sprinkle(int pumpPin) {
  Serial.println("-- Sprinkle Flow Mode --");
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

// Runs the pump in the given mode and then reports the water usage.
void activatePumpMode(int pumpId, int pumpPin, int curMode) {
  switch (curMode) {
    case FAST:
      fast(pumpPin);
      break;
    case SLOW:
      slow(pumpPin);
      break;
    case DRIP:
      drip(pumpPin);
      break;
    case SPRINKLE:
      sprinkle(pumpPin);
      break;
  }
  reportWaterUsage(pumpId, modeLitres(curMode));
}

// Runs the pump when the soil moisture is at or below 30. Note that both branches
// do the same thing, so the temperature and humidity conditions have no effect.
void openPump(int pumpId, int moisturePercent, float tempValue, float humidityValue, int curMode) {
  if (moisturePercent <= 30 && tempValue > 30.0 && humidityValue > 70.0) {
    activatePumpMode(pumpId, pumpPinFor(pumpId), curMode);
  } else if (moisturePercent <= 30) {
    activatePumpMode(pumpId, pumpPinFor(pumpId), curMode);
  }
}

// ---- Setup and the main loop ------------------------------------------------

// Connects to Wi-Fi, opens the socket, starts the HTTP server and the usage
// task, and initialises the sensors.
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
  webSocket.begin(WS_SERVER_URL, WS_SERVER_PORT, WS_PATH);
  webSocket.onEvent(webSocketEvent);
  webSocket.setReconnectInterval(5000);

  usageQueue = xQueueCreate(8, sizeof(UsageReport));
  if (usageQueue != nullptr) {
    xTaskCreate(usageReporterTask, "usageReporter", 4096, nullptr, 1, nullptr);
  } else {
    Serial.println("Could not create the pump water usage queue");
  }

  deviceServer.on("/mode", HTTP_GET, handleGetMode);
  deviceServer.on("/mode", HTTP_POST, handlePostMode);
  deviceServer.begin();
  Serial.println("Pump mode server listening");

  tempSensor1.begin();
  tempSensor2.begin();
  tempSensor3.begin();


  pinMode(PUMP1_PIN, OUTPUT);
  pinMode(PUMP2_PIN, OUTPUT);
  pinMode(PUMP3_PIN, OUTPUT);

  pinMode(MOISTURE_PIN_1, INPUT);
  pinMode(WATER_LEVEL_PIN_1, INPUT);
  pinMode(MOISTURE_PIN_2, INPUT);
  pinMode(WATER_LEVEL_PIN_2, INPUT);
  pinMode(MOISTURE_PIN_3, INPUT);
  pinMode(WATER_LEVEL_PIN_3, INPUT);

  Serial.println("ESP32 Watering System Initialized");
}

// Services the socket and the HTTP server, and every 10 seconds reads each zone,
// publishes the reading and checks whether to water.
void loop() {
  webSocket.loop();
  deviceServer.handleClient();

  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("Wi-Fi disconnected. Reconnecting...");
    WiFi.begin(SSID, PASSWORD);
    while (WiFi.status() != WL_CONNECTED) {
      delay(500);
      Serial.print(".");
    }
    Serial.println("\nWi-Fi reconnected!");
  }

  static unsigned long lastSent = 0;
  if (millis() - lastSent > 10000) {
    lastSent = millis();

    // The pump decision always uses the real readings, even while a garbled
    // reading is being published, so the greenhouse keeps watering itself.
    int moisture1Value = analogRead(MOISTURE_PIN_1);
    int moisture1Percent = map(moisture1Value, MOISTURE_LOW_VAL, MOISTURE_HIGH_VAL, 0, 100);
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
    openPump(1, moisture1Percent, tempSensor1Value, humiditySensor1Value, curMode1);

    int moisture2Value = analogRead(MOISTURE_PIN_2);
    int moisture2Percent = map(moisture2Value, MOISTURE_LOW_VAL, MOISTURE_HIGH_VAL, 0, 100);
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
    openPump(2, moisture2Percent, tempSensor2Value, humiditySensor2Value, curMode2);

    int moisture3Value = analogRead(MOISTURE_PIN_3);
    int moisture3Percent = map(moisture3Value, MOISTURE_LOW_VAL, MOISTURE_HIGH_VAL, 0, 100);
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
    openPump(3, moisture3Percent, tempSensor3Value, humiditySensor3Value, curMode3);
  }
}