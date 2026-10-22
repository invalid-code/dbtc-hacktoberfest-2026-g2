import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/network/sensor_ws.dart';

/// A feed that never opens a socket, the tests push the readings themselves.
class FakeFeed extends SensorFeed {
  FakeFeed() : super(baseUrl: 'ws://localhost:8000');

  @override
  void connect() {}
}

http.Response responseFor(Uri uri) {
  switch (uri.path) {
    case '/sensor/data/':
      return http.Response(
        '[{"id":1,"moisture_level":42,"humidity":78,"temperature":23.5,'
        '"recorded_at":"2026-10-20T16:02:30","sensor_id":1,"garbled":false}]',
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
      return http.Response(
        '[{"id":2,"liters":3.5,"recorded_at":"2026-10-20T16:02:30",'
        '"pump_id":1}]',
        200,
      );
    case '/pump/usage/today':
      return http.Response('{"liters":12.5}', 200);
    case '/alerts/':
      return http.Response(
        '{"alerts":[{"message":"Soil moisture is low","severity":"warning"}]}',
        200,
      );
    default:
      return http.Response('not found', 404);
  }
}

http.Response emptyResponseFor(Uri uri) {
  switch (uri.path) {
    case '/sensor/data/':
      return http.Response('[]', 200);
    case '/pump/history/':
      return http.Response('[]', 200);
    case '/pump/usage/today':
      return http.Response('{"liters":0}', 200);
    case '/alerts/':
      return http.Response('{"alerts":[]}', 200);
    default:
      return responseFor(uri);
  }
}

http.Response garbledResponseFor(Uri uri) {
  switch (uri.path) {
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
      return responseFor(uri);
  }
}

http.Response failingResponseFor(Uri uri) =>
    http.Response('boom', 500);

GreenhouseApi fakeApi(
  http.Response Function(Uri uri) response, {
  List<String>? calls,
}) => GreenhouseApi(
  client: MockClient((request) async {
    calls?.add('${request.method} ${request.url.path}');
    return response(request.url);
  }),
);

/// Waits until the condition is met, the api calls resolve in the background.
Future<void> waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('The condition was not met in time');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}
