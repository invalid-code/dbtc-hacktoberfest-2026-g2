/// The time ranges a graph can be filtered by.
///
/// Every range covers a fixed number of slots ending now. A time range fills
/// the slots with the units of the range — the last 60 minutes, the last 24
/// hours, the last 30 days, the last 12 weeks, the last 12 months or the last
/// 5 years. The real time range fills them with the latest readings, one
/// point each, and keeps them up to date while the readings come in.
enum TimeRange {
  realTime(label: 'Real-time', slots: 60),
  minute(label: 'Minutes', slots: 60),
  hour(label: 'Hours', slots: 24),
  day(label: 'Days', slots: 30),
  week(label: 'Weeks', slots: 12),
  month(label: 'Months', slots: 12),
  year(label: 'Years', slots: 5);

  const TimeRange({required this.label, required this.slots});

  /// The name of the unit, shown in the filter.
  final String label;

  /// How many points the graph shows.
  final int slots;
}
