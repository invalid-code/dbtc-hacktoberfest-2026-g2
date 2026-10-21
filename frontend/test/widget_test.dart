import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/network/sensor_ws.dart';
import 'package:frontend/core/widgets/panel.dart';
import 'package:frontend/main.dart';

class _FakeFeed extends SensorFeed {
  @override
  void connect() {}
}

http.Response _responseFor(String path) {
  switch (path) {
    case '/sensor/data/':
      return http.Response(
        '[{"id":1,"moisture_level":42,"humidity":78,"temperature":23.5,'
        '"recorded_at":"2026-10-20T16:02:30","sensor_id":1}]',
        200,
      );
    case '/pump/':
      return http.Response('[{"id":1},{"id":2},{"id":3}]', 200);
    case '/pump/mode/':
      return http.Response(
        '[{"id":5,"mode":2,"observed_mode":null,"last_seen_at":null,'
        '"pump_id":1}]',
        200,
      );
    case '/pump/history/':
      return http.Response('[]', 200);
    case '/pump/usage/today':
      return http.Response('{"liters":12.5}', 200);
    case '/alerts/':
      return http.Response('{"alerts":[]}', 200);
    default:
      return http.Response('not found', 404);
  }
}

http.Response _emptyResponseFor(String path) {
  switch (path) {
    case '/sensor/data/':
      return http.Response('[]', 200);
    case '/alerts/':
      return http.Response('{"alerts":[]}', 200);
    case '/pump/usage/today':
      return http.Response('{"liters":0}', 200);
    default:
      return _responseFor(path);
  }
}

http.Response _garbledResponseFor(String path) {
  switch (path) {
    case '/sensor/data/':
      return http.Response(
        '[{"id":2,"moisture_level":666,"humidity":999,"temperature":-42.5,'
        '"recorded_at":"2026-10-31T23:59:00","sensor_id":1,"garbled":true}]',
        200,
      );
    case '/alerts/':
      return http.Response(
        '{"alerts":[{"message":"Spooky sensor data detected: the greenhouse is '
        'haunted and the latest readings are unreliable",'
        '"severity":"spooky"}]}',
        200,
      );
    default:
      return _responseFor(path);
  }
}

Widget _app(http.Response Function(String path) response) => GreenhouseApp(
  api: () => GreenhouseApi(
    client: MockClient((request) async => response(request.url.path)),
  ),
  feed: _FakeFeed.new,
);

double _panelHeight(WidgetTester tester, String title) {
  final panel = find.ancestor(
    of: find.text(title),
    matching: find.byType(Panel),
  );
  return tester.getSize(panel.first).height;
}

void main() {
  testWidgets('dashboard renders greenhouse controls', (WidgetTester tester) async {
    await tester.pumpWidget(_app(_responseFor));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Current Conditions'), findsOneWidget);
    expect(find.text('Water Usage History'), findsOneWidget);
    expect(find.text('Water Pump #1'), findsOneWidget);
    expect(find.text('Alerts'), findsOneWidget);

    expect(find.text('42%'), findsOneWidget);
    expect(find.text('78%'), findsOneWidget);
    expect(find.text('12.5 L'), findsOneWidget);
    expect(find.text('Mode: Drip'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('trend panels keep their height without readings', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_app(_emptyResponseFor));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Sensor Readings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('No sensor readings yet'), findsNWidgets(3));
    expect(_panelHeight(tester, 'Temperature Trends'), greaterThan(300));
    expect(_panelHeight(tester, 'Moisture Trends'), greaterThan(300));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('alerts panel keeps its height without alerts', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_app(_emptyResponseFor));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('No alerts'), findsOneWidget);
    expect(_panelHeight(tester, 'Alerts'), greaterThan(300));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('flags garbled readings and shows the spooky alert', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_app(_garbledResponseFor));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('Spooky sensor data detected'), findsOneWidget);
    expect(
      find.textContaining('haunted, the numbers cannot be trusted'),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
