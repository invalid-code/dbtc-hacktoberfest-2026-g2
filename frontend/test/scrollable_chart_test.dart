import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/models/chart_series.dart';
import 'package:frontend/core/models/time_range.dart';
import 'package:frontend/core/widgets/scrollable_chart.dart';

List<ChartBucket> _buckets(int count) {
  return [
    for (var i = 0; i < count; i++)
      ChartBucket(
        start: DateTime(2026, 10, 22, 15, i),
        value: i.toDouble(),
        label: '15:${i.toString().padLeft(2, '0')}',
        fraction: count > 1 ? i / (count - 1) : 1,
      ),
  ];
}

ScrollController _controllerOf(WidgetTester tester) => tester
    .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
    .controller!;

Future<void> _pump(
  WidgetTester tester,
  List<ChartBucket> buckets,
  TimeRange range, {
  double width = 300,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            height: 200,
            child: ScrollableChart(buckets: buckets, range: range),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('a long range scrolls and shows the newest data first', (
    WidgetTester tester,
  ) async {
    await _pump(tester, _buckets(3), TimeRange.day);
    await tester.pumpAndSettle();

    final controller = _controllerOf(tester);
    // Thirty days of fifty pixels do not fit in the three hundred of the box.
    expect(controller.position.maxScrollExtent, 1200);
    expect(controller.offset, 1200);
  });

  testWidgets('a short range fits its parent', (WidgetTester tester) async {
    await _pump(tester, _buckets(5), TimeRange.year, width: 400);
    await tester.pumpAndSettle();

    final controller = _controllerOf(tester);
    expect(controller.position.maxScrollExtent, 0);
    expect(controller.offset, 0);
  });

  testWidgets('the real time width follows the readings', (
    WidgetTester tester,
  ) async {
    await _pump(tester, _buckets(10), TimeRange.realTime);
    await tester.pumpAndSettle();
    expect(_controllerOf(tester).position.maxScrollExtent, 200);

    // Three readings are one hundred and fifty pixels, they fit.
    await _pump(tester, _buckets(3), TimeRange.realTime);
    await tester.pumpAndSettle();
    expect(_controllerOf(tester).position.maxScrollExtent, 0);
  });

  testWidgets('new data does not move a reader who scrolled back', (
    WidgetTester tester,
  ) async {
    await _pump(tester, _buckets(10), TimeRange.realTime);
    await tester.pumpAndSettle();
    final controller = _controllerOf(tester);

    controller.jumpTo(0);
    await tester.pump();
    await _pump(tester, _buckets(12), TimeRange.realTime);
    await tester.pumpAndSettle();
    expect(controller.offset, 0);

    // At the end the graph follows the newest reading.
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();
    await _pump(tester, _buckets(14), TimeRange.realTime);
    await tester.pumpAndSettle();
    expect(controller.offset, controller.position.maxScrollExtent);
  });
}
