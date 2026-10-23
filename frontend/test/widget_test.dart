import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:frontend/core/widgets/panel.dart';
import 'package:frontend/main.dart';

import 'support/fakes.dart';

Widget _app(http.Response Function(Uri uri) response) => GreenhouseApp(
  api: () => fakeApi(response),
  feed: FakeFeed.new,
);

double _panelHeight(WidgetTester tester, String title) {
  final panel = find.ancestor(
    of: find.text(title),
    matching: find.byType(Panel),
  );
  return tester.getSize(panel.first).height;
}

Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('dashboard renders greenhouse controls', (WidgetTester tester) async {
    await tester.pumpWidget(_app(responseFor));
    await _pump(tester);

    expect(find.text('Current Conditions'), findsOneWidget);
    expect(find.text('Water Usage History'), findsOneWidget);
    expect(find.text('Water Pump #1'), findsOneWidget);
    expect(find.text('Alerts'), findsOneWidget);

    expect(find.text('42%'), findsOneWidget);
    expect(find.text('78%'), findsOneWidget);
    expect(find.text('12.5 L'), findsOneWidget);
    expect(find.text('Mode: Drip'), findsOneWidget);
    expect(find.text('Soil moisture is low'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the pump cards follow the pumps the API returns', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    http.Response handler(Uri uri) {
      if (uri.path == '/pump/') {
        return http.Response('[{"id":2},{"id":7}]', 200);
      }
      if (uri.path == '/pump/mode/') {
        return http.Response(
          '[{"id":5,"mode":2,"observed_mode":null,"last_seen_at":null,'
          '"pump_id":2}]',
          200,
        );
      }
      return responseFor(uri);
    }

    await tester.pumpWidget(_app(handler));
    await _pump(tester);

    expect(find.text('Water Pump #1'), findsNothing);
    expect(find.text('Water Pump #2'), findsOneWidget);
    expect(find.text('Water Pump #7'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the app navigates to the watering history', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_app(responseFor));
    await _pump(tester);

    await tester.tap(find.text('Watering History'));
    await _pump(tester);

    expect(find.text('Water Usage History'), findsOneWidget);
    expect(find.text('Pump #1'), findsOneWidget);
    expect(find.text('3.5 L'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the app navigates to the sensor readings', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_app(responseFor));
    await _pump(tester);

    await tester.tap(find.text('Sensor Readings'));
    await _pump(tester);

    expect(find.text('Temperature Trends'), findsOneWidget);
    expect(find.text('Moisture Trends'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('trend panels keep their height without readings', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_app(emptyResponseFor));
    await _pump(tester);

    await tester.tap(find.text('Sensor Readings'));
    await _pump(tester);

    expect(find.text('No sensor readings yet'), findsNWidgets(3));
    expect(_panelHeight(tester, 'Temperature Trends'), greaterThan(300));
    expect(_panelHeight(tester, 'Moisture Trends'), greaterThan(300));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the usage chart can be filtered by another time unit', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_app(responseFor));
    await _pump(tester);

    expect(find.text('Real-time'), findsOneWidget);

    await tester.tap(find.text('Real-time'));
    await tester.pumpAndSettle();

    expect(find.text('Minutes'), findsOneWidget);
    expect(find.text('Years'), findsOneWidget);

    await tester.tap(find.text('Minutes'));
    await tester.pumpAndSettle();

    expect(find.text('Minutes'), findsOneWidget);
    expect(find.text('Real-time'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('alerts panel keeps its height without alerts', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_app(emptyResponseFor));
    await _pump(tester);

    expect(find.text('No alerts'), findsOneWidget);
    expect(_panelHeight(tester, 'Alerts'), greaterThan(300));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('flags garbled readings and shows the spooky alert', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_app(garbledResponseFor));
    await _pump(tester);

    expect(find.textContaining('Spooky sensor data detected'), findsOneWidget);
    expect(
      find.textContaining('haunted, the numbers cannot be trusted'),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the dashboard reports a failing API', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_app(failingResponseFor));
    await _pump(tester);

    expect(find.text('Could not load sensor readings'), findsOneWidget);
    expect(find.text('Could not load alerts'), findsOneWidget);
    expect(find.text('Could not load water usage'), findsOneWidget);
    expect(find.text('Could not load history'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
