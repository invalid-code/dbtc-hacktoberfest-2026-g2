import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:frontend/core/models/time_range.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/features/sensors/data/sensor_reading.dart';

void main() {
  test('parses a sensor reading returned by the API', () {
    final reading = SensorReading.fromJson(const {
      'id': 1,
      'moisture_level': 42,
      'humidity': 78,
      'temperature': 23.5,
      'recorded_at': '2026-10-20T16:02:30.761213',
      'sensor_id': 1,
      'garbled': false,
    });

    expect(reading.moisture, 42);
    expect(reading.humidity, 78);
    expect(reading.temperature, 23.5);
    expect(reading.recordedAt, isNotNull);
    expect(reading.garbled, isFalse);
  });

  test('tells garbled readings apart from the real ones', () {
    final reading = SensorReading.fromJson(const {
      'id': 2,
      'moisture_level': 666,
      'humidity': 999,
      'temperature': -42.5,
      'recorded_at': '2026-10-31T23:59:00',
      'sensor_id': 1,
      'garbled': true,
    });

    expect(reading.garbled, isTrue);
    expect(reading.moisture, 666);
  });

  test('reads the sensor, pump and mode endpoints', () async {
    final requested = <String>[];
    final client = MockClient((request) async {
      requested.add(request.url.path);
      switch (request.url.path) {
        case '/sensor/data/':
          return http.Response(
            '[{"id":1,"moisture_level":42,"humidity":78,"temperature":23.5,'
            '"recorded_at":"2026-10-20T16:02:30","sensor_id":1}]',
            200,
          );
        case '/pump/':
          return http.Response('[{"id":1},{"id":2}]', 200);
        case '/pump/mode/':
          return http.Response(
            '[{"id":5,"mode":2,"observed_mode":null,"last_seen_at":null,'
            '"pump_id":1}]',
            200,
          );
        default:
          return http.Response('not found', 404);
      }
    });

    final api = GreenhouseApi(client: client);

    expect((await api.loadLatestSensorReading())?.humidity, 78);
    expect((await api.loadPumps()).map((pump) => pump.id), [1, 2]);
    expect((await api.loadPumpModes())[1], 2);
    expect(requested, ['/sensor/data/', '/pump/', '/pump/mode/']);
  });

  test('asks for a page of the readings and for the averaged series', () async {
    final requested = <Uri>[];
    final client = MockClient((request) async {
      requested.add(request.url);
      if (request.url.queryParameters['bucket'] != null) {
        return http.Response(
          '[{"start":"2026-10-21T00:00:00","moisture_level":41.5,'
          '"humidity":77.5,"temperature":23.25,"readings":2}]',
          200,
        );
      }
      return http.Response(
        '[{"id":1,"moisture_level":42,"humidity":78,"temperature":23.5,'
        '"recorded_at":"2026-10-20T16:02:30","sensor_id":1}]',
        200,
      );
    });
    final api = GreenhouseApi(client: client);

    await api.loadLatestSensorReading();
    final buckets = await api.loadSensorBuckets(TimeRange.day);

    expect(requested.first.queryParameters, {'limit': '1', 'offset': '0'});
    expect(requested.last.queryParameters, {'bucket': 'day', 'limit': '31'});
    expect(buckets.single.moisture, 41.5);
    expect(buckets.single.readings, 2);
  });

  test('reports a failing endpoint instead of returning empty data', () async {
    final client = MockClient((request) async => http.Response('boom', 500));
    final api = GreenhouseApi(client: client);

    expect(api.loadTodayWaterUsage(), throwsException);
    expect(api.loadAlerts(), throwsException);
    expect(api.loadSensorReadings(), throwsException);
  });
}
