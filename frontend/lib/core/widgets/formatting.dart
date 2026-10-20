import 'package:frontend/features/history/data/pump_history_entry.dart';

String pumpLabel(PumpHistoryEntry entry) =>
    entry.pump == null ? 'Pump' : 'Pump #${entry.pump}';

String formatLiters(double liters) {
  final num value = liters == liters.roundToDouble() ? liters.toInt() : liters;
  return '$value L';
}

String formatTime(DateTime? recordedAt) {
  if (recordedAt == null) return 'Unknown time';
  final hour24 = recordedAt.hour;
  final hour = hour24 % 12 == 0 ? 12 : hour24 % 12;
  final minute = recordedAt.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${hour24 < 12 ? 'AM' : 'PM'}';
}

String formatRecordedAt(DateTime? recordedAt) {
  if (recordedAt == null) return 'Unknown date';
  const months = [
    'Jan.',
    'Feb.',
    'Mar.',
    'Apr.',
    'May',
    'Jun.',
    'Jul.',
    'Aug.',
    'Sep.',
    'Oct.',
    'Nov.',
    'Dec.',
  ];
  return '${months[recordedAt.month - 1]} ${recordedAt.day}, '
      '${recordedAt.year} · ${formatTime(recordedAt)}';
}
