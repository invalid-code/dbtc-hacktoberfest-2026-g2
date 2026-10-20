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