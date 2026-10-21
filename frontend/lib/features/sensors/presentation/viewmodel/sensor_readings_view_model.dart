import 'package:flutter/foundation.dart';

import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/features/sensors/data/sensor_reading.dart';

/// Holds the sensor readings shown by the sensor readings screen.
class SensorReadingsViewModel extends ChangeNotifier {
  SensorReadingsViewModel({GreenhouseApi? api})
    : _api = api ?? GreenhouseApi();

  final GreenhouseApi _api;

  List<SensorReading>? readings;
  bool failed = false;

  void start() => _load();

  Future<void> _load() async {
    try {
      readings = await _api.loadSensorReadings();
    } catch (_) {
      failed = true;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }
}
