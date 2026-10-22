import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:frontend/core/models/chart_series.dart';
import 'package:frontend/core/models/time_range.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/network/sensor_ws.dart';
import 'package:frontend/features/history/data/pump_history_entry.dart';
import 'package:frontend/features/sensors/data/sensor_reading.dart';
import 'package:frontend/model/alert.dart';
import 'package:frontend/model/pump_info.dart';

/// Holds the state of the dashboard and notifies the view through a
/// `ListenableBuilder`.
class HomeViewModel extends ChangeNotifier {
  HomeViewModel({GreenhouseApi? api, SensorFeed? feed})
    : _api = api ?? GreenhouseApi(),
      _feed = feed ?? SensorFeed();

  final GreenhouseApi _api;
  final SensorFeed _feed;
  StreamSubscription<SensorReading>? _sensorSub;
  bool _disposed = false;

  // A null value means the request is still loading, the matching ...Failed
  // flag means the request failed.
  GreenhouseSnapshot? snapshot;
  double? todayUsageLiters;
  List<Alert>? alerts;
  List<ChartBucket>? usageBuckets;
  List<PumpHistoryEntry>? history;
  bool snapshotFailed = false;
  bool usageFailed = false;
  bool alertsFailed = false;
  bool historyFailed = false;

  /// The time unit the usage chart is filtered by.
  TimeRange usageRange = TimeRange.month;

  /// The biggest amount of water of a bucket, the chart is scaled to it.
  double get usageMaxLiters {
    final buckets = usageBuckets ?? const <ChartBucket>[];
    if (buckets.isEmpty) return 1;
    return buckets.map((bucket) => bucket.value).reduce((a, b) => a > b ? a : b);
  }

  int pumpIdFor(int index) =>
      snapshot != null && snapshot!.pumps.length > index
          ? snapshot!.pumps[index].id
          : index + 1;

  int? pumpModeFor(int index) =>
      snapshot != null && snapshot!.pumps.length > index
          ? snapshot!.pumps[index].mode
          : null;

  /// Loads everything in parallel and then connects the live feed.
  void start() {
    _loadInitial();
    _feed.connect();
    _sensorSub = _feed.readings.listen(_onSensorReading);
  }

  Future<void> _loadInitial() async {
    await Future.wait([
      _loadSnapshot(),
      _loadUsage(),
      _loadAlerts(),
      _loadHistory(),
    ]);
  }

  Future<void> _loadSnapshot() async {
    var failed = false;

    SensorReading? sensor;
    try {
      sensor = await _api.loadLatestSensorReading();
    } catch (_) {
      failed = true;
    }

    var pumps = <PumpInfo>[];
    try {
      pumps = await _api.loadPumps();
    } catch (_) {
      failed = true;
    }

    var modes = <int, int>{};
    try {
      modes = await _api.loadPumpModes();
    } catch (_) {
      failed = true;
    }

    snapshotFailed = failed;
    snapshot = GreenhouseSnapshot(
      sensor: sensor,
      pumps: pumps
          .map((pump) => PumpInfo(id: pump.id, mode: modes[pump.id]))
          .toList(),
    );
    _notify();
  }

  Future<void> _loadUsage() async {
    try {
      todayUsageLiters = await _api.loadTodayWaterUsage();
    } catch (_) {
      usageFailed = true;
    }
    _notify();
  }

  Future<void> _loadAlerts() async {
    try {
      alerts = await _api.loadAlerts();
    } catch (_) {
      alertsFailed = true;
    }
    _notify();
  }

  Future<void> _loadHistory() async {
    try {
      final entries = await _api.loadPumpHistory();
      history = entries;
      usageBuckets = usageBucketsFrom(entries, usageRange);
    } catch (_) {
      historyFailed = true;
    }
    _notify();
  }

  /// Filters the usage chart by another time unit.
  void setUsageRange(TimeRange range) {
    if (range == usageRange) return;
    usageRange = range;
    usageBuckets = usageBucketsFrom(history ?? const [], range);
    _notify();
  }

  /// A live reading replaces the sensor of the snapshot, the pumps are kept.
  void _onSensorReading(SensorReading reading) {
    final current = snapshot;
    snapshot = GreenhouseSnapshot(
      sensor: reading,
      pumps: current?.pumps ?? const [],
    );
    _notify();
  }

  /// Writes the mode to the API and then applies it to the local snapshot.
  Future<void> updatePumpMode(int pump, int mode) async {
    await _api.updatePumpMode(pump, mode);
    _applyPumpMode(pump, mode);
  }

  void _applyPumpMode(int pump, int mode) {
    final current = snapshot;
    if (current == null) return;
    snapshot = GreenhouseSnapshot(
      sensor: current.sensor,
      pumps: current.pumps
          .map(
            (item) => item.id == pump ? PumpInfo(id: item.id, mode: mode) : item,
          )
          .toList(),
    );
    _notify();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  /// The water usage of every unit of the range, the litres of a unit added
  /// up.
  static List<ChartBucket> usageBucketsFrom(
    List<PumpHistoryEntry> entries,
    TimeRange range,
  ) {
    return ChartSeries.group(
      points: [
        for (final entry in entries)
          if (entry.recordedAt != null)
            ChartPoint(at: entry.recordedAt!, value: entry.liters),
      ],
      range: range,
      mode: BucketMode.sum,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _sensorSub?.cancel();
    _api.dispose();
    _feed.dispose();
    super.dispose();
  }
}
