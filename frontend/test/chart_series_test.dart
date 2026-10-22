import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/models/chart_series.dart';
import 'package:frontend/core/models/time_range.dart';

void main() {
  group('ChartSeries', () {
    test('groups the points into the minutes', () {
      final now = DateTime(2026, 10, 22, 15, 30);
      final buckets = ChartSeries.group(
        points: [
          ChartPoint(at: DateTime(2026, 10, 22, 15, 28), value: 1),
          ChartPoint(at: DateTime(2026, 10, 22, 15, 29), value: 3),
          ChartPoint(at: DateTime(2026, 10, 22, 15, 12), value: 5),
        ],
        range: TimeRange.minute,
        now: now,
      );

      expect(buckets.length, 3);
      expect(buckets[0].value, 5);
      expect(buckets[0].label, '15:12');
      expect(buckets[1].value, 1);
      expect(buckets[1].label, '15:28');
      expect(buckets[2].value, 3);
      expect(buckets[2].label, '15:29');
    });

    test('averages the points of a bucket', () {
      final now = DateTime(2026, 10, 22, 15, 30);
      final buckets = ChartSeries.group(
        points: [
          ChartPoint(at: DateTime(2026, 10, 22, 14, 10), value: 1),
          ChartPoint(at: DateTime(2026, 10, 22, 14, 40), value: 3),
          ChartPoint(at: DateTime(2026, 10, 22, 15, 5), value: 5),
        ],
        range: TimeRange.hour,
        mode: BucketMode.average,
        now: now,
      );

      expect(buckets.length, 2);
      expect(buckets[0].value, 2);
      expect(buckets[0].label, '14:00');
      expect(buckets[1].value, 5);
      expect(buckets[1].label, '15:00');
    });

    test('adds the points of a bucket up', () {
      final now = DateTime(2026, 10, 22, 15, 30);
      final buckets = ChartSeries.group(
        points: [
          ChartPoint(at: DateTime(2026, 10, 22, 14, 10), value: 1),
          ChartPoint(at: DateTime(2026, 10, 22, 14, 40), value: 3),
        ],
        range: TimeRange.hour,
        mode: BucketMode.sum,
        now: now,
      );

      expect(buckets.length, 1);
      expect(buckets.first.value, 4);
    });

    test('leaves the points outside of the range out', () {
      final now = DateTime(2026, 10, 22, 15, 30);
      final buckets = ChartSeries.group(
        points: [
          ChartPoint(at: DateTime(2026, 10, 22, 15, 10), value: 2),
          ChartPoint(at: DateTime(2026, 10, 22, 10), value: 1),
          ChartPoint(at: DateTime(2026, 10, 22, 15, 40), value: 9),
        ],
        range: TimeRange.minute,
        now: now,
      );

      expect(buckets.length, 1);
      expect(buckets.first.value, 2);
    });

    test('labels the days of the axis', () {
      final buckets = ChartSeries.group(
        points: [ChartPoint(at: DateTime(2026, 10, 20, 9), value: 1)],
        range: TimeRange.day,
        now: DateTime(2026, 10, 22, 15, 30),
      );

      expect(buckets.single.label, 'OCT 20');
    });

    test('labels the months of the axis', () {
      final buckets = ChartSeries.group(
        points: [ChartPoint(at: DateTime(2026, 8, 5), value: 1)],
        range: TimeRange.month,
        now: DateTime(2026, 10, 22, 15, 30),
      );

      expect(buckets.single.label, 'AUG');
    });

    test('labels the years of the axis', () {
      final buckets = ChartSeries.group(
        points: [ChartPoint(at: DateTime(2024, 3, 5), value: 1)],
        range: TimeRange.year,
        now: DateTime(2026, 10, 22, 15, 30),
      );

      expect(buckets.single.label, '2024');
    });

    test('the weeks start on monday', () {
      final monday = DateTime(2026, 10, 19);
      expect(monday.weekday, DateTime.monday);

      final buckets = ChartSeries.group(
        points: [
          ChartPoint(at: monday.add(const Duration(hours: 9)), value: 1),
        ],
        range: TimeRange.week,
        now: DateTime(2026, 10, 22, 15, 30),
      );

      expect(buckets.length, 1);
      expect(buckets.first.start, monday);
      expect(buckets.first.label, 'OCT 19');
    });

    test('the points of a range are spaced by their time', () {
      final now = DateTime(2026, 10, 22, 15, 30);
      final buckets = ChartSeries.group(
        points: [
          // Two days of the last 30, ten days apart.
          ChartPoint(at: DateTime(2026, 10, 20, 9), value: 1),
          ChartPoint(at: DateTime(2026, 10, 10, 9), value: 2),
        ],
        range: TimeRange.day,
        now: now,
      );

      expect(buckets.length, 2);
      // 2 days and 12 days of the 29 the window is wide, the ten days
      // between them are a gap on the axis.
      expect(buckets[0].fraction, closeTo(17 / 29, 0.001));
      expect(buckets[1].fraction, closeTo(27 / 29, 0.001));
    });

    test('the real time points are spaced by their time', () {
      final buckets = ChartSeries.group(
        points: [
          ChartPoint(at: DateTime(2026, 10, 22, 15, 10), value: 2),
          // Three minutes after the first of the nine the span covers.
          ChartPoint(at: DateTime(2026, 10, 22, 15, 13), value: 3),
          ChartPoint(at: DateTime(2026, 10, 22, 15, 19), value: 5),
        ],
        range: TimeRange.realTime,
        now: DateTime(2026, 10, 22, 15, 30),
      );

      expect(buckets.length, 3);
      expect(buckets[0].fraction, 0);
      expect(buckets[1].fraction, closeTo(1 / 3, 0.001));
      expect(buckets[2].fraction, 1);
    });

    test('the real time points of the same moment are spread evenly', () {
      final at = DateTime(2026, 10, 22, 15, 30);
      final buckets = ChartSeries.group(
        points: [
          ChartPoint(at: at, value: 2),
          ChartPoint(at: at, value: 3),
        ],
        range: TimeRange.realTime,
        now: at,
      );

      expect(buckets[0].fraction, 0);
      expect(buckets[1].fraction, 1);
    });

    test('the real time range keeps the latest points of their own', () {
      final buckets = ChartSeries.group(
        points: [
          ChartPoint(at: DateTime(2026, 10, 22, 15, 10), value: 2),
          ChartPoint(at: DateTime(2026, 10, 22, 15, 20), value: 3),
          ChartPoint(at: DateTime(2026, 10, 22, 15, 30), value: 5),
        ],
        range: TimeRange.realTime,
        now: DateTime(2026, 10, 22, 15, 30),
      );

      expect(buckets.length, 3);
      expect(buckets[0].value, 2);
      expect(buckets[0].label, '15:10');
      expect(buckets[2].value, 5);
      expect(buckets[2].label, '15:30');
    });

    test('the real time range drops the points that do not fit', () {
      final points = [
        for (var i = 0; i < 70; i++)
          ChartPoint(
            at: DateTime(2026, 10, 22, 15, 30).subtract(Duration(minutes: i)),
            value: i.toDouble(),
          ),
      ];

      final buckets = ChartSeries.group(
        points: points,
        range: TimeRange.realTime,
        now: DateTime(2026, 10, 22, 15, 30),
      );

      expect(buckets.length, 60);
      expect(buckets.first.value, 59);
      expect(buckets.last.value, 0);
    });

    test('the real time range sorts the points by time', () {
      final buckets = ChartSeries.group(
        points: [
          ChartPoint(at: DateTime(2026, 10, 22, 15, 30), value: 5),
          ChartPoint(at: DateTime(2026, 10, 22, 15, 10), value: 2),
        ],
        range: TimeRange.realTime,
        now: DateTime(2026, 10, 22, 15, 30),
      );

      expect(buckets.length, 2);
      expect(buckets.first.value, 2);
      expect(buckets.last.value, 5);
    });
  });
}
