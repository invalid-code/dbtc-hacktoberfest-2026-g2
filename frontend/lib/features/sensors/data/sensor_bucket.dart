/// The readings that fall in one unit of time, averaged by the API.
///
/// A chart asks for the buckets of its range instead of every reading behind
/// them, so it only downloads the points it draws.
class SensorBucket {
  const SensorBucket({
    required this.start,
    required this.moisture,
    required this.humidity,
    required this.readings,
    this.temperature,
  });

  /// The moment the unit starts, null when the API sent no usable moment.
  final DateTime? start;

  final double moisture;
  final double humidity;
  final double? temperature;

  /// How many readings were averaged into this bucket.
  final int readings;

  factory SensorBucket.fromJson(Map<String, dynamic> json) => SensorBucket(
    start: json['start'] == null
        ? null
        : DateTime.tryParse(json['start'] as String? ?? ''),
    moisture: (json['moisture_level'] as num?)?.toDouble() ?? 0,
    humidity: (json['humidity'] as num?)?.toDouble() ?? 0,
    temperature: (json['temperature'] as num?)?.toDouble(),
    readings: (json['readings'] as num?)?.toInt() ?? 0,
  );
}
