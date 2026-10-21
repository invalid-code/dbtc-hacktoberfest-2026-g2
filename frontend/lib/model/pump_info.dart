/// The pump modes, in the order of the API `PumpModeName` enum and the Arduino
/// `OperatingMode` enum, so the index of a label is the ordinal stored in the
/// database.
const pumpModeLabels = ['Fast', 'Slow', 'Drip', 'Sprinkle'];

/// The label of a mode ordinal, an unknown or missing mode falls back to
/// `Fast`.
String pumpModeLabel(int? mode) =>
    mode == null || mode < 0 || mode >= pumpModeLabels.length
    ? pumpModeLabels.first
    : pumpModeLabels[mode];

/// A pump of the greenhouse, `mode` is the ordinal of the mode it runs in.
class PumpInfo {
  const PumpInfo({required this.id, required this.mode});

  final int id;
  final int? mode;

  factory PumpInfo.fromJson(Map<String, dynamic> json) => PumpInfo(
    id: (json['id'] as num).toInt(),
    mode: (json['mode'] as num?)?.toInt(),
  );
}
