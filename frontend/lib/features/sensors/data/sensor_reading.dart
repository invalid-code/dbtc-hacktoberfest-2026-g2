/// A sensor reading, the shape comes from the API and from the websocket.
///
/// The `garbled` flag marks a halloween easter egg reading that must not be
/// trusted.
class SensorReading {
  const SensorReading({
    required this.moisture,
    required this.humidity,
    required this.recordedAt,
    this.temperature,
    this.garbled = false,
  });

  final int moisture;
  final int humidity;
  final DateTime? recordedAt;
  final double? temperature;

  /// The microcontroller garbles the readings as a halloween easter egg, these
  /// readings must not be trusted.
  final bool garbled;

  factory SensorReading.fromJson(Map<String, dynamic> json) => SensorReading(
    moisture: (json['moisture_level'] as num?)?.toInt() ?? 0,
    humidity: (json['humidity'] as num?)?.toInt() ?? 0,
    recordedAt: json['recorded_at'] == null
        ? null
        : DateTime.tryParse(json['recorded_at'] as String? ?? ''),
    temperature: (json['temperature'] as num?)?.toDouble(),
    garbled: json['garbled'] == true,
  );
}
