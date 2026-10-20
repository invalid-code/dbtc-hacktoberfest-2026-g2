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

const _requestTimeout = Duration(seconds: 10);

class GreenhouseSnapshot {
  const GreenhouseSnapshot({required this.sensor, required this.pumps});

  final SensorReading? sensor;
  final List<PumpInfo> pumps;
}

class GreenhouseApi {
  GreenhouseApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<SensorReading?> loadLatestSensorReading() async {
    final readings = await loadSensorReadings();
    return readings.isEmpty ? null : readings.last;
  }

  Future<List<SensorReading>> loadSensorReadings() async {
    final response = await _get('/sensor/data/');
    return _asList(response)
        .map(SensorReading.fromJson)
        .toList()
      ..sort(
        (a, b) => Comparable.compare(
          a.recordedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
          b.recordedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
        ),
      );
  }

  Future<List<PumpInfo>> loadPumps() async {
    final response = await _get('/pump/');
    return _asList(response)
        .map((json) => PumpInfo(id: (json['id'] as num).toInt(), mode: null))
        .toList();
  }

  Future<Map<int, int>> loadPumpModes() async {
    final response = await _get('/pump/mode/');
    final modes = <int, int>{};
    for (final mode in _asList(response)) {
      final pumpId = (mode['pump_id'] as num?)?.toInt();
      if (pumpId == null) continue;
      modes[pumpId] = (mode['mode'] as num?)?.toInt() ?? 0;
    }
    return modes;
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
    return _asList(response).map(PumpHistoryEntry.fromJson).toList();
  }

  Future<double> loadTodayWaterUsage() async {
    final response = await _get('/pump/usage/today');
    if (response is! Map<String, dynamic>) {
      throw const FormatException('Expected a JSON object for water usage');
    }
    return (response['liters'] as num?)?.toDouble() ?? 0;
  }

  Future<List<Alert>> loadAlerts() async {
    final response = await _get('/alerts/');
    if (response is! Map<String, dynamic>) {
      throw const FormatException('Expected a JSON object for alerts');
    }
    final alerts = response['alerts'];
    if (alerts is! List) return const [];
    return alerts
        .whereType<Map<String, dynamic>>()
        .map(Alert.fromJson)
        .toList();
  }

  List<Map<String, dynamic>> _asList(dynamic response) {
    if (response is! List) {
      throw const FormatException('Expected a JSON list');
    }
    return response.whereType<Map<String, dynamic>>().toList();
  }

  Future<dynamic> _get(String path) async {
    final response = await _client
        .get(
          Uri.parse('$apiBaseUrl$path'),
          headers: const {'Accept': 'application/json'},
        )
        .timeout(_requestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'GET $path failed: ${response.statusCode} ${response.body}',
      );
    }
    return _decode(response);
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
                headers: const {
                  'Content-Type': 'application/json',
                  'Accept': 'application/json',
                },
                body: jsonEncode(body),
              )
              .timeout(_requestTimeout)
        : throw UnsupportedError(method);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        '$method $path failed: ${response.statusCode} ${response.body}',
      );
    }
  }

  dynamic _decode(http.Response response) {
    if (response.body.isEmpty) return null;
    try {
      return jsonDecode(response.body);
    } on FormatException catch (error) {
      throw FormatException('Invalid JSON from the API: ${error.message}');
    }
  }

  void dispose() {
    _client.close();
  }
}
