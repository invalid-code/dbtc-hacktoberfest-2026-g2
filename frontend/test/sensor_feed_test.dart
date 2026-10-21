import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/network/sensor_ws.dart';
import 'package:frontend/features/sensors/data/sensor_reading.dart';

void main() {
  group('sensorReadingFromMessage', () {
    test('reads a reading sent by the microcontroller', () {
      final reading = sensorReadingFromMessage(
        jsonEncode({
          'sensor': 1,
          'moisture_level': 42,
          'humidity': 78,
          'temperature': 23.5,
          'recorded_at': '2026-10-20T16:02:30',
          'garbled': false,
        }),
      );

      expect(reading, isNotNull);
      expect(reading!.moisture, 42);
      expect(reading.humidity, 78);
      expect(reading.temperature, 23.5);
      expect(reading.recordedAt, DateTime(2026, 10, 20, 16, 2, 30));
      expect(reading.garbled, isFalse);
    });

    test('keeps the garbled flag of a haunted reading', () {
      final reading = sensorReadingFromMessage(
        jsonEncode({
          'sensor': 1,
          'moisture_level': 666,
          'humidity': 999,
          'temperature': -42.5,
          'garbled': true,
        }),
      );

      expect(reading?.garbled, isTrue);
    });

    test('ignores a message that is not a reading', () {
      expect(sensorReadingFromMessage(jsonEncode({'hello': 'world'})), isNull);
    });

    test('ignores a message that is not json', () {
      expect(sensorReadingFromMessage('not json'), isNull);
      expect(sensorReadingFromMessage(42), isNull);
    });
  });

  group('SensorFeed', () {
    test('publishes the readings it receives', () async {
      final feed = SensorFeed(baseUrl: 'ws://localhost:8000');
      final readings = <int>[];

      feed.readings.listen((reading) => readings.add(reading.moisture));
      feed.publish(
        const SensorReading(
          moisture: 42,
          humidity: 78,
          recordedAt: null,
          temperature: 23.5,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(readings, [42]);

      feed.dispose();
    });

    test('a disposed feed does not publish anymore', () async {
      final feed = SensorFeed(baseUrl: 'ws://localhost:8000');
      final readings = <int>[];

      feed.readings.listen((reading) => readings.add(reading.moisture));
      feed.dispose();
      feed.publish(
        const SensorReading(
          moisture: 42,
          humidity: 78,
          recordedAt: null,
          temperature: 23.5,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(readings, isEmpty);
    });
  });
}
