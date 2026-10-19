import 'dart:convert';

import 'package:http/http.dart' as http;

final apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:8000',
).replaceFirst(RegExp(r'/$'), '');

class SensorReading {
  const SensorReading({
    required this.moisture,
    required this.waterLevel,
    required this.recordedAt,
  });

  final int moisture;
  final int waterLevel;
  final DateTime? recordedAt;

  factory SensorReading.fromJson(Map<String, dynamic> json) => SensorReading(
    moisture: (json['moisture_level'] as num?)?.toInt() ?? 0,
    waterLevel: (json['water_level'] as num?)?.toInt() ?? 0,
    recordedAt: json['recorded_at'] == null
        ? null
        : DateTime.tryParse(json['recorded_at'] as String),
  );
}

class PumpInfo {
  const PumpInfo({required this.id, required this.mode});

  final int id;
  final int? mode;

  factory PumpInfo.fromJson(Map<String, dynamic> json) => PumpInfo(
    id: (json['id'] as num).toInt(),
    mode: (json['mode'] as num?)?.toInt(),
  );
}

class PumpHistoryEntry {
  const PumpHistoryEntry({
    required this.pump,
    required this.liters,
    required this.recordedAt,
  });

  final int? pump;
  final double liters;
  final DateTime? recordedAt;

  factory PumpHistoryEntry.fromJson(Map<String, dynamic> json) =>
      PumpHistoryEntry(
        pump: (json['pump_id'] as num?)?.toInt(),
        liters: (json['liters'] as num?)?.toDouble() ?? 0,
        recordedAt: json['recorded_at'] == null
            ? null
            : DateTime.tryParse(json['recorded_at'] as String),
      );
}

class Alert {
  const Alert({required this.message, required this.severity});

  final String message;
  final String severity;

  factory Alert.fromJson(Map<String, dynamic> json) => Alert(
    message: (json['message'] as String?) ?? '',
    severity: (json['severity'] as String?) ?? 'warning',
  );
}

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
      _get('/sensor-data/'),
      _get('/pump/'),
      _get('/pump-mode/'),
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
    final response = await _get('/sensor-data/');
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
      '/pump-mode/',
      method: 'PUT',
      body: {'pump': pump, 'pump_mode': pumpMode},
    );
  }

  Future<List<PumpHistoryEntry>> loadPumpHistory() async {
    final response = await _get('/pump-history/');
    return (response as List)
        .whereType<Map<String, dynamic>>()
        .map(PumpHistoryEntry.fromJson)
        .toList();
  }

  Future<double> loadTodayWaterUsage() async {
    final response = await _get('/usage/today/');
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
