import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:frontend/core/models/chart_series.dart';
import 'package:frontend/core/models/time_range.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/network/sensor_ws.dart';
import 'package:frontend/features/sensors/data/sensor_reading.dart';

/// Holds the sensor readings shown by the sensor readings screen.
///
/// The readings of the API are loaded once and the live feed adds the
/// readings that come in, so the graphs keep up to date.
class SensorReadingsViewModel extends ChangeNotifier {
  SensorReadingsViewModel({GreenhouseApi? api, SensorFeed? feed})
    : _api = api ?? GreenhouseApi(),
      _feed = feed ?? SensorFeed();

  final GreenhouseApi _api;
  final SensorFeed _feed;
  StreamSubscription<SensorReading>? _sensorSub;

  List<SensorReading>? readings;
  bool failed = false;

  /// The readings that came in over the live feed, they are kept so they are
  /// not lost when the readings of the API arrive.
  final List<SensorReading> _liveReadings = [];

  /// The time unit the temperature chart is filtered by.
  TimeRange temperatureRange = TimeRange.realTime;

  /// The time unit the moisture chart is filtered by.
  TimeRange moistureRange = TimeRange.realTime;

  /// The temperature of every point of the range.
  List<ChartBucket> temperatureBuckets = const [];

  /// The moisture of every point of the range.
  List<ChartBucket> moistureBuckets = const [];

  void start() {
    _load();
    _feed.connect();
    _sensorSub = _feed.readings.listen(_onSensorReading);
  }

  Future<void> _load() async {
    try {
      final loaded = await _api.loadSensorReadings();
      readings = [...loaded, ..._liveReadings];
      _rebuildBuckets();
    } catch (_) {
      failed = true;
    }
    notifyListeners();
  }

  /// A live reading joins the readings and the graphs are rebuilt.
  void _onSensorReading(SensorReading reading) {
    _liveReadings.add(reading);
    readings = [...?readings, reading];
    _rebuildBuckets();
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

  /// Groups the readings into the points of the two ranges.
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

  /// The values of the readings, grouped by the unit of the range.
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
    _sensorSub?.cancel();
    _api.dispose();
    _feed.dispose();
    super.dispose();
  }
}
