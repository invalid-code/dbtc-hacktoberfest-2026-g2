#include <WiFi.h>
#include <WebSocketsClient.h>
#include <ArduinoJson.h>
#include <stdlib.h>

#include "secrets.h"

IPAddress local_IP(192, 168, 1, 184);
IPAddress gateway(192, 168, 1, 1);
IPAddress subnet(255, 255, 255, 0);

IPAddress primaryDNS(1, 1, 1, 1);
IPAddress secondaryDNS(1, 0, 0, 1);

WebSocketsClient webSocket;

enum OperatingMode {
  FAST,
  SLOW,
  DRIP,
  SPRINKLE
};

const int PUMP1_PIN = 25;
const int PUMP2_PIN = 26;
const int PUMP3_PIN = 27;

const int MOISTURE_PIN_1 = 34;
const int WATER_LEVEL_PIN_1 = 35;
const int MOISTURE_PIN_2 = 32;
const int WATER_LEVEL_PIN_2 = 33;
const int MOISTURE_PIN_3 = 36;
const int WATER_LEVEL_PIN_3 = 39;

const int MOISTURE_LOW_VAL = 0;
const int MOISTURE_HIGH_VAL = 2800;
const int WATER_LEVEL_LOW_VAL = 0;
const int WATER_LEVEL_HIGH_VAL = 1400;

int curMode1 = FAST;
int curMode2 = FAST;
int curMode3 = FAST;

void setPumpMode(int* pump, int pumpMode) {
  switch (pumpMode) {
    case 0:
      *pump = FAST;
      break;
    case 1:
      *pump = SLOW;
      break;
    case 2:
      *pump = DRIP;
      break;
    case 3:
      *pump = SPRINKLE;
      break;
  }
}

void webSocketEvent(WStype_t type, uint8_t* payload, size_t length) {
  switch (type) {
    case WStype_DISCONNECTED:
      Serial.println("Disconnected!");
      break;

    case WStype_CONNECTED:
      Serial.printf("Connected to url: %s\n", payload);
      break;

    case WStype_TEXT:
      Serial.printf("Received pump mode: %s\n", payload);

      {
        JsonDocument doc;
        DeserializationError error = deserializeJson(doc, payload, length);

        if (error) {
          Serial.print("deserializeJson() failed: ");
          Serial.println(error.c_str());
          return;
        }

        int pump = doc["pump"];
        int pumpMode = doc["pump_mode"];

        switch (pump) {
          case 1:
            setPumpMode(&curMode1, pumpMode);
            break;
          case 2:
            setPumpMode(&curMode2, pumpMode);
            break;
          case 3:
            setPumpMode(&curMode3, pumpMode);
            break;
        }
      }
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

void fast(int pumpPin) {
  Serial.println("-- Fast Flow Mode --");
  digitalWrite(pumpPin, HIGH);
  delay(750);
  digitalWrite(pumpPin, LOW);
}

void slow(int pumpPin) {
  Serial.println("-- Slow Flow Mode --");
  analogWrite(pumpPin, 120);
  delay(750);
  analogWrite(pumpPin, 0);
}

void drip(int pumpPin) {
  Serial.println("-- Drip Flow Mode --");
  digitalWrite(pumpPin, HIGH);
  delay(150);

  digitalWrite(pumpPin, LOW);
  delay(2500);
}

void sprinkle(int pumpPin) {
  Serial.println("-- Sprinkle Flow Mode --");
}

void sendSensorData(int sensor, int moisturePercent, int waterLevelPercent) {
  if (WiFi.status() == WL_CONNECTED) {
    JsonDocument doc;
    doc["sensor"] = sensor;
    doc["moisture_level"] = moisturePercent;
    doc["water_level"] = waterLevelPercent;

    String jsonString;
    serializeJson(doc, jsonString);
    webSocket.sendTXT(jsonString);
    Serial.println("Sent sensor data payload");
  }
}

void openPump(int moisturePercent, int waterLevelPercent, int pump, int curMode) {
  if (moisturePercent <= 30 && waterLevelPercent >= 30) {
    switch (curMode) {
      case FAST:
        fast(pump);
        break;
      case SLOW:
        slow(pump);
        break;
      case DRIP:
        drip(pump);
        break;
      case SPRINKLE:
        sprinkle(pump);
        break;
    }
  } else {

  }
}

void setup() {
  Serial.begin(115200);

  WiFi.begin(SSID, PASSWORD);
  Serial.println("Connecting");
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("");
  Serial.print("Connected to WiFi network with IP Address: ");
  Serial.println(WiFi.localIP());

  webSocket.begin(SERVER_URL, SERVER_PORT, WS_PATH);
  webSocket.onEvent(webSocketEvent);
  webSocket.setReconnectInterval(5000);

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

void loop() {
  webSocket.loop();

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

    int moisture1Value = analogRead(MOISTURE_PIN_1);
    int moisture1Percent = map(moisture1Value, MOISTURE_LOW_VAL, MOISTURE_HIGH_VAL, 0, 100);
    moisture1Percent = constrain(moisture1Percent, 0, 100);
    Serial.print("Soil moisture 1 raw: ");
    Serial.println(moisture1Value);
    Serial.print("Soil moisture 1 percentage: ");
    Serial.println(moisture1Percent);

    int waterLevel1Value = analogRead(WATER_LEVEL_PIN_1);
    int waterLevel1Percent = map(waterLevel1Value, WATER_LEVEL_LOW_VAL, WATER_LEVEL_HIGH_VAL, 0, 100);
    waterLevel1Percent = constrain(waterLevel1Percent, 0, 100);
    Serial.print("Water level 1 raw: ");
    Serial.println(waterLevel1Value);
    Serial.print("Water level 1 percentage: ");
    Serial.println(waterLevel1Percent);

    sendSensorData(1, moisture1Percent, waterLevel1Percent);
    openPump(moisture1Percent, waterLevel1Percent, PUMP1_PIN, curMode1);

    int moisture2Value = analogRead(MOISTURE_PIN_2);
    int moisture2Percent = map(moisture2Value, MOISTURE_LOW_VAL, MOISTURE_HIGH_VAL, 0, 100);
    moisture2Percent = constrain(moisture2Percent, 0, 100);
    Serial.print("Soil moisture 2 raw: ");
    Serial.println(moisture2Value);
    Serial.print("Soil moisture 2 percentage: ");
    Serial.println(moisture2Percent);

    int waterLevel2Value = analogRead(WATER_LEVEL_PIN_2);
    int waterLevel2Percent = map(waterLevel2Value, WATER_LEVEL_LOW_VAL, WATER_LEVEL_HIGH_VAL, 0, 100);
    waterLevel2Percent = constrain(waterLevel2Percent, 0, 100);
    Serial.print("Water level 2 raw: ");
    Serial.println(waterLevel2Value);
    Serial.print("Water level 2 percentage: ");
    Serial.println(waterLevel2Percent);

    sendSensorData(2, moisture2Percent, waterLevel2Percent);
    openPump(moisture2Percent, waterLevel2Percent, PUMP2_PIN, curMode2);

    int moisture3Value = analogRead(MOISTURE_PIN_3);
    int moisture3Percent = map(moisture3Value, MOISTURE_LOW_VAL, MOISTURE_HIGH_VAL, 0, 100);
    moisture3Percent = constrain(moisture3Percent, 0, 100);
    Serial.print("Soil moisture 3 raw: ");
    Serial.println(moisture3Value);
    Serial.print("Soil moisture 3 percentage: ");
    Serial.println(moisture3Percent);

    int waterLevel3Value = analogRead(WATER_LEVEL_PIN_3);
    int waterLevel3Percent = map(waterLevel3Value, WATER_LEVEL_LOW_VAL, WATER_LEVEL_HIGH_VAL, 0, 100);
    waterLevel3Percent = constrain(waterLevel3Percent, 0, 100);
    Serial.print("Water level 3 raw: ");
    Serial.println(waterLevel3Value);
    Serial.print("Water level 3 percentage: ");
    Serial.println(waterLevel3Percent);

    sendSensorData(3, moisture3Percent, waterLevel3Percent);
    openPump(moisture3Percent, waterLevel3Percent, PUMP3_PIN, curMode3);
  }
}