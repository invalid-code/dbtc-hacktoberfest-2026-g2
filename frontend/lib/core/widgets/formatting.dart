import 'package:frontend/features/history/data/pump_history_entry.dart';

/// The three letter names of the months, used by the axis of the graphs.
const shortMonthNames = [
  'JAN',
  'FEB',
  'MAR',
  'APR',
  'MAY',
  'JUN',
  'JUL',
  'AUG',
  'SEP',
  'OCT',
  'NOV',
  'DEC',
];

/// The name of the pump of a watering record, `Pump` when the pump is unknown.
String pumpLabel(PumpHistoryEntry entry) =>
    entry.pump == null ? 'Pump' : 'Pump #${entry.pump}';

/// A number without the decimals when it is whole.
String formatNumber(double value) {
  final num number = value == value.roundToDouble() ? value.toInt() : value;
  return '$number';
}

/// The volume in liters, without decimals when the amount is whole.
String formatLiters(double liters) => '${formatNumber(liters)} L';

/// The time of a reading as `h:mm AM/PM`.
String formatTime(DateTime? recordedAt) {
  if (recordedAt == null) return 'Unknown time';
  final hour24 = recordedAt.hour;
  final hour = hour24 % 12 == 0 ? 12 : hour24 % 12;
  final minute = recordedAt.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${hour24 < 12 ? 'AM' : 'PM'}';
}

/// The date and the time of a reading.
///
/// The dates are formatted by hand because `intl` is not a dependency.
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
