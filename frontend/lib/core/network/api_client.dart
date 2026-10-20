import 'dart:convert';

import 'package:frontend/features/history/data/pump_history_entry.dart';
import 'package:frontend/features/sensors/data/sensor_reading.dart';
import 'package:frontend/model/alert.dart';
import 'package:frontend/model/pump_info.dart';
import 'package:http/http.dart' as http;

const _apiBaseUrlRaw = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:8000',
);

final apiBaseUrl = _apiBaseUrlRaw.endsWith('/')
    ? _apiBaseUrlRaw.substring(0, _apiBaseUrlRaw.length - 1)
    : _apiBaseUrlRaw;

class GreenhouseSnapshot {
  const GreenhouseSnapshot({required this.sensor, required this.pumps});

  final SensorReading? sensor;
  final List<PumpInfo> pumps;
}

class GreenhouseApi {
  GreenhouseApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<GreenhouseSnapshot> loadSnapshot() async {
    final responses = await Future.wait([
      _get('/sensor/data/'),
      _get('/pump/'),
      _get('/pump/mode/'),
    ]);
    final sensors =
        (responses[0] as List)
            .whereType<Map<String, dynamic>>()
            .map(SensorReading.fromJson)
            .toList()
          ..sort(
            (a, b) => Comparable.compare(
              a.recordedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
              b.recordedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
            ),
          );
    final pumps = (responses[1] as List)
        .whereType<Map<String, dynamic>>()
        .map((json) => PumpInfo(id: (json['id'] as num).toInt(), mode: null))
        .toList();
    final modes = (responses[2] as List).whereType<Map<String, dynamic>>();
    final modeByPump = {
      for (final mode in modes)
        (mode['pump_id'] as num).toInt(): (mode['mode'] as num).toInt(),
    };

    return GreenhouseSnapshot(
      sensor: sensors.isEmpty ? null : sensors.last,
      pumps: pumps
          .map((pump) => PumpInfo(id: pump.id, mode: modeByPump[pump.id]))
          .toList(),
    );
  }

  Future<List<SensorReading>> loadSensorReadings() async {
    final response = await _get('/sensor/data/');
    final readings =
        (response as List)
            .whereType<Map<String, dynamic>>()
            .map(SensorReading.fromJson)
            .toList()
          ..sort(
            (a, b) => Comparable.compare(
              a.recordedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
              b.recordedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
            ),
          );
    return readings;
  }

  Future<void> updatePumpMode(int pump, int pumpMode) async {
    await _request(
      '/pump/mode/',
      method: 'PUT',
      body: {'pump': pump, 'pump_mode': pumpMode},
    );
  }

  Future<List<PumpHistoryEntry>> loadPumpHistory() async {
    final response = await _get('/pump/history/');
    return (response as List)
        .whereType<Map<String, dynamic>>()
        .map(PumpHistoryEntry.fromJson)
        .toList();
  }

  Future<double> loadTodayWaterUsage() async {
    final response = await _get('/pump/usage/today');
    return (response['liters'] as num?)?.toDouble() ?? 0;
  }

  Future<List<Alert>> loadAlerts() async {
    final response = await _get('/alerts/');
    return (response['alerts'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(Alert.fromJson)
        .toList();
  }

  Future<dynamic> _get(String path) async {
    final response = await _client
        .get(Uri.parse('$apiBaseUrl$path'))
        .timeout(const Duration(seconds: 3));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('GET $path failed: ${response.statusCode}');
    }
    return jsonDecode(response.body);
  }

  Future<void> _request(
    String path, {
    required String method,
    required Map<String, dynamic> body,
  }) async {
    final uri = Uri.parse('$apiBaseUrl$path');
    final response = method == 'PUT'
        ? await _client
              .put(
                uri,
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode(body),
              )
              .timeout(const Duration(seconds: 3))
        : throw UnsupportedError(method);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('$method $path failed: ${response.statusCode}');
    }
  }

  void dispose() {
    _client.close();
  }
}
