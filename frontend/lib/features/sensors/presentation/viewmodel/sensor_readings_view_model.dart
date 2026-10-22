import 'package:flutter/foundation.dart';

import 'package:frontend/core/models/chart_series.dart';
import 'package:frontend/core/models/time_range.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/features/sensors/data/sensor_reading.dart';

/// Holds the sensor readings shown by the sensor readings screen.
class SensorReadingsViewModel extends ChangeNotifier {
  SensorReadingsViewModel({GreenhouseApi? api})
    : _api = api ?? GreenhouseApi();

  final GreenhouseApi _api;

  List<SensorReading>? readings;
  bool failed = false;

  /// The time unit the temperature chart is filtered by.
  TimeRange temperatureRange = TimeRange.hour;

  /// The time unit the moisture chart is filtered by.
  TimeRange moistureRange = TimeRange.hour;

  /// The temperature of every unit of the range, averaged.
  List<ChartBucket> temperatureBuckets = const [];

  /// The moisture of every unit of the range, averaged.
  List<ChartBucket> moistureBuckets = const [];

  void start() => _load();

  Future<void> _load() async {
    try {
      readings = await _api.loadSensorReadings();
      _rebuildBuckets();
    } catch (_) {
      failed = true;
    }
    notifyListeners();
  }

  /// Filters the temperature chart by another time unit.
  void setTemperatureRange(TimeRange range) {
    if (range == temperatureRange) return;
    temperatureRange = range;
    _rebuildBuckets();
    notifyListeners();
  }

  /// Filters the moisture chart by another time unit.
  void setMoistureRange(TimeRange range) {
    if (range == moistureRange) return;
    moistureRange = range;
    _rebuildBuckets();
    notifyListeners();
  }

  /// Groups the readings into the buckets of the two ranges.
  void _rebuildBuckets() {
    temperatureBuckets = _buckets(
      (reading) => reading.temperature ?? 0,
      temperatureRange,
    );
    moistureBuckets = _buckets(
      (reading) => reading.moisture.toDouble(),
      moistureRange,
    );
  }

  /// The values of the readings, averaged per unit of the range.
  List<ChartBucket> _buckets(
    double Function(SensorReading) value,
    TimeRange range,
  ) {
    final entries = readings ?? const <SensorReading>[];
    return ChartSeries.group(
      points: [
        for (final reading in entries)
          if (reading.recordedAt != null)
            ChartPoint(at: reading.recordedAt!, value: value(reading)),
      ],
      range: range,
      mode: BucketMode.average,
    );
  }

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }
}
