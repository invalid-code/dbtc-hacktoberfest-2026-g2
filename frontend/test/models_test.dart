import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/features/history/data/pump_history_entry.dart';
import 'package:frontend/features/sensors/data/sensor_reading.dart';
import 'package:frontend/model/alert.dart';
import 'package:frontend/model/pump_info.dart';

void main() {
  group('SensorReading', () {
    test('reads every field of a reading', () {
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
      expect(reading.recordedAt, DateTime(2026, 10, 20, 16, 2, 30, 761, 213));
      expect(reading.garbled, isFalse);
    });

    test('tells a garbled reading apart from a real one', () {
      final reading = SensorReading.fromJson(const {
        'moisture_level': 666,
        'humidity': 999,
        'temperature': -42.5,
        'garbled': true,
      });

      expect(reading.garbled, isTrue);
      expect(reading.moisture, 666);
    });

    test('falls back to zero when a value is missing', () {
      final reading = SensorReading.fromJson(const {});

      expect(reading.moisture, 0);
      expect(reading.humidity, 0);
      expect(reading.temperature, isNull);
      expect(reading.recordedAt, isNull);
      expect(reading.garbled, isFalse);
    });

    test('survives a broken timestamp', () {
      final reading = SensorReading.fromJson(const {'recorded_at': 'not a date'});

      expect(reading.recordedAt, isNull);
    });
  });

  group('PumpHistoryEntry', () {
    test('reads every field of an entry', () {
      final entry = PumpHistoryEntry.fromJson(const {
        'id': 2,
        'liters': 3.5,
        'recorded_at': '2026-10-20T16:02:30',
        'pump_id': 1,
      });

      expect(entry.liters, 3.5);
      expect(entry.pump, 1);
      expect(entry.recordedAt, DateTime(2026, 10, 20, 16, 2, 30));
    });

    test('copes with an entry without a pump', () {
      final entry = PumpHistoryEntry.fromJson(const {'liters': 1.0});

      expect(entry.pump, isNull);
      expect(entry.liters, 1.0);
    });
  });

  group('Alert', () {
    test('reads the message and the severity', () {
      final alert = Alert.fromJson(const {
        'message': 'Soil moisture is low',
        'severity': 'warning',
      });

      expect(alert.message, 'Soil moisture is low');
      expect(alert.severity, 'warning');
    });

    test('falls back to a warning', () {
      final alert = Alert.fromJson(const {});

      expect(alert.message, '');
      expect(alert.severity, 'warning');
    });
  });

  group('pump modes', () {
    test('the labels match the mode indexes of the API', () {
      expect(pumpModeLabels, ['Fast', 'Slow', 'Drip', 'Sprinkle']);
      expect(pumpModeLabel(0), 'Fast');
      expect(pumpModeLabel(1), 'Slow');
      expect(pumpModeLabel(2), 'Drip');
      expect(pumpModeLabel(3), 'Sprinkle');
    });

    test('an unknown mode falls back to fast', () {
      expect(pumpModeLabel(null), 'Fast');
      expect(pumpModeLabel(9), 'Fast');
      expect(pumpModeLabel(-1), 'Fast');
    });
  });
}
