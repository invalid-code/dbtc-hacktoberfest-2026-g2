class PumpInfo {
  const PumpInfo({required this.id, required this.mode});

  final int id;
  final int? mode;

  factory PumpInfo.fromJson(Map<String, dynamic> json) => PumpInfo(
    id: (json['id'] as num).toInt(),
    mode: (json['mode'] as num?)?.toInt(),
  );
}