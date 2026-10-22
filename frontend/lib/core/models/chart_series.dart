import 'package:frontend/core/models/time_range.dart';
import 'package:frontend/core/widgets/formatting.dart';

/// A point of a graph, the value of a reading at a moment.
class ChartPoint {
  const ChartPoint({required this.at, required this.value});

  final DateTime at;
  final double value;
}

/// A bucket of a graph: the value of the unit it covers and the label of the
/// unit on the x axis.
class ChartBucket {
  const ChartBucket({
    required this.start,
    required this.value,
    required this.label,
    required this.fraction,
  });

  /// The moment the unit of the bucket starts.
  final DateTime start;

  /// The value of the unit, summed or averaged depending on the mode.
  final double value;

  /// The label of the unit on the x axis.
  final String label;

  /// How far along the x axis the bucket sits, 0 at the left edge and 1 at
  /// the right edge.
  ///
  /// It follows the time of the bucket, so the distance between two points is
  /// the time between them and a unit without data leaves a gap.
  final double fraction;
}

/// How the values of the points of a bucket are combined.
enum BucketMode {
  /// The values of the bucket are added up, for the water usage.
  sum,

  /// The values of the bucket are averaged, for the sensor readings.
  average,
}

/// Groups the points of a graph into the buckets of a time range.
class ChartSeries {
  const ChartSeries._();

  /// The buckets of the range that hold at least one point, oldest first.
  ///
  /// The buckets of a range end now, the oldest one is `range.slots` units
  /// old. The points outside of the range are dropped and the buckets without
  /// a point are left out, so the graph only shows the units with data.
  ///
  /// The real time range does not group the points by a unit of time, it
  /// keeps the latest points of the range, one bucket each.
  static List<ChartBucket> group({
    required List<ChartPoint> points,
    required TimeRange range,
    BucketMode mode = BucketMode.sum,
    DateTime? now,
  }) {
    if (range == TimeRange.realTime) return _latest(points, range);

    final end = now ?? DateTime.now();
    final totals = List<double>.filled(range.slots, 0);
    final counts = List<int>.filled(range.slots, 0);
    for (final point in points) {
      final index = _indexOf(point.at, end, range);
      if (index < 0 || index >= range.slots) continue;
      // The buckets are counted from now backwards, the list runs the other
      // way around.
      final slot = range.slots - 1 - index;
      totals[slot] += point.value;
      counts[slot] += 1;
    }

    final buckets = <ChartBucket>[];
    for (var slot = 0; slot < range.slots; slot++) {
      if (counts[slot] == 0) continue;
      final start = _startOf(range, end, range.slots - 1 - slot);
      buckets.add(
        ChartBucket(
          start: start,
          value: mode == BucketMode.average
              ? totals[slot] / counts[slot]
              : totals[slot],
          label: _labelOf(range, start),
          fraction: _fractionOf(start, end, range),
        ),
      );
    }
    return buckets;
  }

  /// The latest points of the range, one bucket each, the oldest first.
  ///
  /// Every point is a reading of its own, so the mode does not apply.
  static List<ChartBucket> _latest(List<ChartPoint> points, TimeRange range) {
    final sorted = [...points]..sort((a, b) => a.at.compareTo(b.at));
    final start = sorted.length > range.slots
        ? sorted.length - range.slots
        : 0;
    final latest = sorted.sublist(start);
    if (latest.isEmpty) return const [];
    final first = latest.first.at;
    final span = latest.last.at.difference(first).inMilliseconds;
    return [
      for (var i = 0; i < latest.length; i++)
        ChartBucket(
          start: latest[i].at,
          value: latest[i].value,
          label: _timeLabel(latest[i].at),
          // The points are spread over the time they cover, the time between
          // two readings is the distance between them.
          fraction: span > 0
              ? latest[i].at.difference(first).inMilliseconds / span
              : latest.length > 1
              ? i / (latest.length - 1)
              : 1,
        ),
    ];
  }

  /// How far along the x axis a unit of the range sits, 0 at the left edge
  /// and 1 at the right edge.
  static double _fractionOf(DateTime start, DateTime end, TimeRange range) {
    final span = range.slots - 1;
    if (span <= 0) return 1;
    return (span - _indexOf(start, end, range)) / span;
  }

  /// How many units of the range separate the moment from the end of the
  /// range, 0 for the unit that is running right now.
  static int _indexOf(DateTime at, DateTime end, TimeRange range) {
    switch (range) {
      case TimeRange.minute:
        return _minutes(end) - _minutes(at);
      case TimeRange.hour:
        return _hours(end) - _hours(at);
      case TimeRange.day:
        return _days(end) - _days(at);
      case TimeRange.week:
        return (_days(_monday(end)) - _days(_monday(at))) ~/ 7;
      case TimeRange.month:
        return (end.year - at.year) * 12 + end.month - at.month;
      case TimeRange.year:
        return end.year - at.year;
      case TimeRange.realTime:
        return 0;
    }
  }

  /// The moment the unit of the bucket starts, `index` counts from now
  /// backwards.
  static DateTime _startOf(TimeRange range, DateTime end, int index) {
    switch (range) {
      case TimeRange.minute:
        return DateTime(
          end.year,
          end.month,
          end.day,
          end.hour,
          end.minute - index,
        );
      case TimeRange.hour:
        return DateTime(end.year, end.month, end.day, end.hour - index);
      case TimeRange.day:
        return DateTime(end.year, end.month, end.day - index);
      case TimeRange.week:
        final monday = _monday(end);
        return DateTime(monday.year, monday.month, monday.day - 7 * index);
      case TimeRange.month:
        return DateTime(end.year, end.month - index);
      case TimeRange.year:
        return DateTime(end.year - index);
      case TimeRange.realTime:
        return end;
    }
  }

  /// The label of the unit on the x axis.
  static String _labelOf(TimeRange range, DateTime start) {
    switch (range) {
      case TimeRange.minute:
        return '${_pad(start.hour)}:${_pad(start.minute)}';
      case TimeRange.hour:
        return '${_pad(start.hour)}:00';
      case TimeRange.day:
      case TimeRange.week:
        return '${shortMonthNames[start.month - 1]} ${start.day}';
      case TimeRange.month:
        return shortMonthNames[start.month - 1];
      case TimeRange.year:
        return '${start.year}';
      case TimeRange.realTime:
        return _timeLabel(start);
    }
  }

  /// The time of a point on the x axis.
  static String _timeLabel(DateTime at) => '${_pad(at.hour)}:${_pad(at.minute)}';

  /// The Monday of the week the moment belongs to.
  static DateTime _monday(DateTime at) =>
      DateTime(at.year, at.month, at.day - (at.weekday - 1));

  /// The minutes since the epoch of the wall clock of the moment.
  static int _minutes(DateTime at) =>
      DateTime.utc(at.year, at.month, at.day, at.hour, at.minute)
          .millisecondsSinceEpoch ~/
      60000;

  /// The hours since the epoch of the wall clock of the moment.
  static int _hours(DateTime at) =>
      DateTime.utc(at.year, at.month, at.day, at.hour).millisecondsSinceEpoch ~/
      3600000;

  /// The days since the epoch of the wall clock of the moment.
  static int _days(DateTime at) =>
      DateTime.utc(at.year, at.month, at.day).millisecondsSinceEpoch ~/ 86400000;

  static String _pad(int value) => value.toString().padLeft(2, '0');
}
