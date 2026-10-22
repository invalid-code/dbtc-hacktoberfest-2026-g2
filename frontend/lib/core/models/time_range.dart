/// The time units a graph can be filtered by.
///
/// Every range covers a fixed number of buckets ending now, one bucket per
/// unit: the last 60 minutes, the last 24 hours, the last 30 days, the last
/// 12 weeks, the last 12 months or the last 5 years.
enum TimeRange {
  minute(label: 'Minutes', buckets: 60),
  hour(label: 'Hours', buckets: 24),
  day(label: 'Days', buckets: 30),
  week(label: 'Weeks', buckets: 12),
  month(label: 'Months', buckets: 12),
  year(label: 'Years', buckets: 5);

  const TimeRange({required this.label, required this.buckets});

  /// The name of the unit, shown in the filter.
  final String label;

  /// How many buckets the graph shows, one per unit of the range.
  final int buckets;
}
