class SensorReading {
  const SensorReading({
    required this.moisture,
    required this.humidity,
    required this.recordedAt,
    this.temperature,
  });

  final int moisture;
  final int humidity;
  final DateTime? recordedAt;
  final double? temperature;

  factory SensorReading.fromJson(Map<String, dynamic> json) => SensorReading(
    moisture: (json['moisture_level'] as num?)?.toInt() ?? 0,
    humidity: (json['humidity'] as num?)?.toInt() ?? 0,
    recordedAt: json['recorded_at'] == null
        ? null
        : DateTime.tryParse(json['recorded_at'] as String? ?? ''),
    temperature: (json['temperature'] as num?)?.toDouble(),
  );
}
