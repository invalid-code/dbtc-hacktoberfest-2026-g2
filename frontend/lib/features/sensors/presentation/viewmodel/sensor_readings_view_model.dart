import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:frontend/core/models/chart_series.dart';
import 'package:frontend/core/models/time_range.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/network/sensor_ws.dart';
import 'package:frontend/features/sensors/data/sensor_bucket.dart';
import 'package:frontend/features/sensors/data/sensor_reading.dart';

/// Holds the sensor readings shown by the sensor readings screen.
///
/// The latest readings feed the real time graphs, while every other range is
/// downloaded already averaged per unit, so the graphs only fetch the points
/// they draw. The live feed keeps the graphs up to date.
class SensorReadingsViewModel extends ChangeNotifier {
  SensorReadingsViewModel({GreenhouseApi? api, SensorFeed? feed})
    : _api = api ?? GreenhouseApi(),
      _feed = feed ?? SensorFeed();

  /// How long the live readings are batched before the averaged series is
  /// fetched again, so a burst of readings costs a single request.
  static const _seriesRefreshDelay = Duration(seconds: 5);

  final GreenhouseApi _api;
  final SensorFeed _feed;
  StreamSubscription<SensorReading>? _sensorSub;
  Timer? _seriesRefresh;

  List<SensorReading>? readings;
  bool failed = false;

  /// The readings that came in over the live feed, they are kept so they are
  /// not lost when the readings of the API arrive.
  final List<SensorReading> _liveReadings = [];

  /// The averaged readings the API already sent, per range.
  final Map<TimeRange, List<SensorBucket>> _series = {};

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
      final loaded = await _api.loadSensorReadings(
        limit: TimeRange.realTime.slots,
      );
      readings = [...loaded, ..._liveReadings];
      await _ensureSeries(temperatureRange);
      await _ensureSeries(moistureRange);
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
    if (_series.isNotEmpty) _scheduleSeriesRefresh();
  }

  /// Filters the temperature chart by another time unit.
  Future<void> setTemperatureRange(TimeRange range) async {
    if (range == temperatureRange) return;
    temperatureRange = range;
    // The chip follows the tap before the series is fetched.
    notifyListeners();
    await _selectRange(range);
  }

  /// Filters the moisture chart by another time unit.
  Future<void> setMoistureRange(TimeRange range) async {
    if (range == moistureRange) return;
    moistureRange = range;
    notifyListeners();
    await _selectRange(range);
  }

  /// Fetches the series of a range when it was never fetched, then rebuilds
  /// the graphs.
  Future<void> _selectRange(TimeRange range) async {
    await _ensureSeries(range);
    _rebuildBuckets();
    notifyListeners();
  }

  /// The averaged series of the range, fetched once and then cached.
  Future<void> _ensureSeries(TimeRange range) async {
    if (range == TimeRange.realTime || _series.containsKey(range)) return;
    try {
      _series[range] = await _api.loadSensorBuckets(range);
    } catch (_) {
      failed = true;
    }
  }

  /// Fetches the cached series again, after the live readings changed them.
  void _scheduleSeriesRefresh() {
    _seriesRefresh ??= Timer(_seriesRefreshDelay, () {
      _seriesRefresh = null;
      _refreshSeries();
    });
  }

  Future<void> _refreshSeries() async {
    for (final range in _series.keys.toList()) {
      try {
        _series[range] = await _api.loadSensorBuckets(range);
      } catch (_) {
        failed = true;
      }
    }
    _rebuildBuckets();
    notifyListeners();
  }

  /// Groups the readings into the points of the two ranges.
  void _rebuildBuckets() {
    temperatureBuckets = _buckets(
      temperatureRange,
      (reading) => reading.temperature ?? 0,
      (bucket) => bucket.temperature ?? 0,
    );
    moistureBuckets = _buckets(
      moistureRange,
      (reading) => reading.moisture.toDouble(),
      (bucket) => bucket.moisture,
    );
  }

  /// The values of the readings, grouped by the unit of the range.
  ///
  /// The real time range groups the latest readings itself; every other range
  /// shows the buckets the API already averaged.
  List<ChartBucket> _buckets(
    TimeRange range,
    double Function(SensorReading) readingValue,
    double Function(SensorBucket) bucketValue,
  ) {
    if (range == TimeRange.realTime) {
      return ChartSeries.group(
        points: [
          for (final reading in readings ?? const <SensorReading>[])
            if (reading.recordedAt != null)
              ChartPoint(at: reading.recordedAt!, value: readingValue(reading)),
        ],
        range: range,
        mode: BucketMode.average,
      );
    }
    return ChartSeries.group(
      points: [
        for (final bucket in _series[range] ?? const <SensorBucket>[])
          if (bucket.start != null)
            ChartPoint(at: bucket.start!, value: bucketValue(bucket)),
      ],
      range: range,
      mode: BucketMode.average,
    );
  }

  @override
  void dispose() {
    _sensorSub?.cancel();
    _seriesRefresh?.cancel();
    _api.dispose();
    _feed.dispose();
    super.dispose();
  }
}
