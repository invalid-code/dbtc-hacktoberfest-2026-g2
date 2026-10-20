// TODO need to know how much water was used and send the data to the backend

#include <WiFi.h>
#include <WebSocketsClient.h>
#include <ArduinoJson.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "DHT.h"
#include <HTTPClient.h>

#include "secrets.h"

#define DHTPIN1 4
#define DHTPIN2 16
#define DHTPIN3 17

#define DHTTYPE DHT11

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

const int PUMP1_PIN = 25;
const int PUMP2_PIN = 26;
const int PUMP3_PIN = 27;

const int MOISTURE_PIN_1 = 36;
const int WATER_LEVEL_PIN_1 = 39;
const int MOISTURE_PIN_2 = 35;
const int WATER_LEVEL_PIN_2 = 32;
const int MOISTURE_PIN_3 = 25;
const int WATER_LEVEL_PIN_3 = 26;

const int MOISTURE_LOW_VAL = 0;
const int MOISTURE_HIGH_VAL = 2800;
const int WATER_LEVEL_LOW_VAL = 0;
const int WATER_LEVEL_HIGH_VAL = 1400;

const int PUMP_MODE_CONTROL = 0;
const int PUMP_ACTIVATE_CONTROL = 1;

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

        int pumpControl = doc["pump_control"];
        int pump = doc["pump"];
        switch (pumpControl) {
          case PUMP_MODE_CONTROL:
            {
              int pumpMode = doc["pump_mode"];
              int* curMode;

              switch (pump) {
                case 1:
                  curMode = &curMode1;
                  break;
                case 2:
                  curMode = &curMode2;
                  break;
                case 3:
                  curMode = &curMode3;
                  break;
              }
              setPumpMode(curMode, pumpMode);
              break;
            }
          case PUMP_ACTIVATE_CONTROL:
            // for now only activate based on cur mode of a pump
            {
              int curMode = 0;
              switch (pump) {
                case 1:
                  curMode = curMode1;
                  break;
                case 2:
                  curMode = curMode2;
                  break;
                case 3:
                  curMode = curMode3;
                  break;
              }
              openPump(PUMP_ACTIVATE_CONTROL, 0, 0, 0, pump, curMode);
              break;
            }
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

void sendPumpWaterUsage(int pump, float waterUsage) {
  if (WiFi.status() == WL_CONNECTED) {
    WiFiClient client;
    HTTPClient http;

    size_t serverUrlStrLen = strlen(SERVER_URL);
    size_t pumpHistoryStrLen = strlen(PUMP_HISTORY_PATH);
    char* serverStr = (char*)malloc((serverUrlStrLen + pumpHistoryStrLen) * sizeof(char));
    sprintf(serverStr, "%s%s", SERVER_URL, PUMP_HISTORY_PATH);

    http.begin(client, serverStr);
    http.addHeader("Content-Type", "application/json");
    char* httpRequestData = (char*)malloc(1);
    int httpResponseCode = http.POST(httpRequestData);

    Serial.println("Sent pump water usage data payload");
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

void sendSensorData(int sensor, int moisturePercent, float tempSensorValue, float humiditySensorValue) {
  if (WiFi.status() == WL_CONNECTED) {
    JsonDocument doc;
    doc["sensor"] = sensor;
    doc["moisture_level"] = moisturePercent;
    doc["temperature"] = tempSensorValue;
    doc["humidity"] = tempSensorValue;

    String jsonString;
    serializeJson(doc, jsonString);
    webSocket.sendTXT(jsonString);
    Serial.println("Sent sensor data payload");
  }
}

void activatePumpMode(int pump, int curMode) {
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
  sendPumpWaterUsage(pump);
}

void openPump(int pumpControl, int moisturePercent, float tempValue, float humidityValue, int pump, int curMode) {
  // on the occasion that the conditions should allow for both to activate prioritize the PUMP_ACTIVATE_CONTROL
  if (pumpControl == PUMP_ACTIVATE_CONTROL) {
    activatePumpMode(pump, curMode);
  } else {
    if (moisturePercent <= 30 && tempValue > 30.0 && humidityValue > 70.0) {
      activatePumpMode(pump, curMode);
    } else if (moisturePercent <= 30) {
      activatePumpMode(pump, curMode);
    }
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


    float tempSensor1Value = tempSensor1.readTemperature();
    Serial.print("Temperature 1 raw: ");
    Serial.println(tempSensor1Value);

    float humiditySensor1Value = tempSensor1.readHumidity();
    Serial.print("Humidity 1 raw: ");
    Serial.println(humiditySensor1Value);

    sendSensorData(1, moisture1Percent, tempSensor1Value, humiditySensor1Value);                 // TODO need to make magic value for sensor numbers
    openPump(0, moisture1Percent, tempSensor1Value, humiditySensor1Value, PUMP1_PIN, curMode1);  // not PUMP_ACTIVATE_CONTROL

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

    sendSensorData(2, moisture2Percent, tempSensor2Value, humiditySensor2Value);                 // TODO need to make magic value for sensor numbers
    openPump(0, moisture2Percent, tempSensor2Value, humiditySensor2Value, PUMP2_PIN, curMode2);  // not PUMP_ACTIVATE_CONTROL

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

    sendSensorData(3, moisture3Percent, tempSensor3Value, humiditySensor3Value);                 // TODO need to make magic value for sensor numbers
    openPump(0, moisture3Percent, tempSensor3Value, humiditySensor3Value, PUMP3_PIN, curMode3);  // not PUMP_ACTIVATE_CONTROL
  }
}