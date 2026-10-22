/// The time ranges a graph can be filtered by.
///
/// Every range covers a fixed number of slots ending now. A time range fills
/// the slots with the units of the range — the last 60 minutes, the last 24
/// hours, the last 30 days, the last 12 weeks, the last 12 months or the last
/// 5 years. The real time range fills them with the latest readings, one
/// point each, and keeps them up to date while the readings come in.
enum TimeRange {
  realTime(label: 'Real-time', slots: 60),
  minute(label: 'Minutes', slots: 60, unit: 'minute'),
  hour(label: 'Hours', slots: 24, unit: 'hour'),
  day(label: 'Days', slots: 30, unit: 'day'),
  week(label: 'Weeks', slots: 12, unit: 'week'),
  month(label: 'Months', slots: 12, unit: 'month'),
  year(label: 'Years', slots: 5, unit: 'year');

  const TimeRange({required this.label, required this.slots, this.unit});

  /// The name of the unit, shown in the filter.
  final String label;

  /// How many points the graph shows.
  final int slots;

  /// The unit the API groups the readings of the range by, as named by its
  /// `bucket` parameter.
  ///
  /// It is null for the real time range, which shows the latest readings
  /// instead of grouping them.
  final String? unit;
}
