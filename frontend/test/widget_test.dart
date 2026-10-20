import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/network/sensor_ws.dart';
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

void main() {
  testWidgets('dashboard renders greenhouse controls', (WidgetTester tester) async {
    await tester.pumpWidget(
      GreenhouseApp(
        api: () => GreenhouseApi(
          client: MockClient(
            (request) async => _responseFor(request.url.path),
          ),
        ),
        feed: _FakeFeed.new,
      ),
    );
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
}
