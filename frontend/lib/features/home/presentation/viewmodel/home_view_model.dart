import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/network/sensor_ws.dart';
import 'package:frontend/features/history/data/pump_history_entry.dart';
import 'package:frontend/features/sensors/data/sensor_reading.dart';
import 'package:frontend/model/alert.dart';

class HomeViewModel extends ChangeNotifier {
  HomeViewModel({GreenhouseApi? api, SensorFeed? feed})
    : _api = api ?? GreenhouseApi(),
      _feed = feed ?? SensorFeed();

  final GreenhouseApi _api;
  final SensorFeed _feed;
  StreamSubscription<SensorReading>? _sensorSub;

  GreenhouseSnapshot? snapshot;
  double? todayUsageLiters;
  List<Alert>? alerts;
  List<double>? monthlyUsage;
  List<PumpHistoryEntry>? history;
  bool usageFailed = false;
  bool alertsFailed = false;
  bool historyFailed = false;

  int pumpIdFor(int index) =>
      snapshot != null && snapshot!.pumps.length > index
          ? snapshot!.pumps[index].id
          : index + 1;

  void start() {
    _loadInitial();
    _sensorSub = _feed.readings.listen(_onSensorReading);
  }

  Future<void> _loadInitial() async {
    try {
      snapshot = await _api.loadSnapshot();
      notifyListeners();
    } catch (_) {}

    try {
      todayUsageLiters = await _api.loadTodayWaterUsage();
      notifyListeners();
    } catch (_) {
      usageFailed = true;
      notifyListeners();
    }

    try {
      alerts = await _api.loadAlerts();
      notifyListeners();
    } catch (_) {
      alertsFailed = true;
      notifyListeners();
    }

    try {
      final entries = await _api.loadPumpHistory();
      history = entries;
      monthlyUsage = entries.isEmpty ? const [] : monthlyUsageFrom(entries);
      notifyListeners();
    } catch (_) {
      historyFailed = true;
      notifyListeners();
    }
  }

  void _onSensorReading(SensorReading reading) {
    snapshot = GreenhouseSnapshot(
      sensor: reading,
      pumps: snapshot?.pumps ?? const [],
    );
    notifyListeners();
  }

  static List<double> monthlyUsageFrom(List<PumpHistoryEntry> entries) {
    final year = DateTime.now().year;
    final totals = List<double>.filled(12, 0);
    for (final entry in entries) {
      final at = entry.recordedAt;
      if (at == null || at.year != year) continue;
      totals[at.month - 1] += entry.liters;
    }
    final max = totals.reduce((a, b) => a > b ? a : b);
    if (max <= 0) return totals;
    return totals.map((value) => value / max).toList();
  }

  @override
  void dispose() {
    _sensorSub?.cancel();
    _api.dispose();
    _feed.dispose();
    super.dispose();
  }
}
