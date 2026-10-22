import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:frontend/core/models/time_range.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/network/sensor_ws.dart';
import 'package:frontend/features/sensors/data/sensor_reading.dart';
import 'package:frontend/main.dart';

import 'support/fakes.dart';

/// The app mounted with the given response handler and live feed.
Widget _app(
  http.Response Function(Uri uri) response, {
  SensorFeed Function()? feed,
}) => GreenhouseApp(api: () => fakeApi(response), feed: feed ?? FakeFeed.new);

/// Lets the initial requests resolve and the first frame paint.
Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// Picks an entry of an open dropdown or popup menu.
Future<void> _select(WidgetTester tester, String label) async {
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('changing a pump mode sends its ordinal and updates the card', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.method == 'PUT') {
        return http.Response(
          '{"id":5,"mode":3,"observed_mode":null,"last_seen_at":null,'
          '"pump_id":1}',
          200,
        );
      }
      return responseFor(request.url);
    });
    final api = GreenhouseApi(client: client);

    await tester.pumpWidget(GreenhouseApp(api: () => api, feed: FakeFeed.new));
    await _pump(tester);

    expect(find.text('Mode: Drip'), findsOneWidget);

    await tester.tap(find.byType(DropdownButton<String>).first);
    await _select(tester, 'Mode: Sprinkle');

    final put = requests.singleWhere((request) => request.method == 'PUT');
    expect(put.url.path, '/pump/mode/');
    expect(jsonDecode(put.body), {'pump': 1, 'pump_mode': 3});
    expect(find.text('Mode: Sprinkle'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a failed pump mode change rolls back and warns the user', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final client = MockClient((request) async {
      if (request.method == 'PUT') return http.Response('boom', 500);
      return responseFor(request.url);
    });

    await tester.pumpWidget(
      GreenhouseApp(
        api: () => GreenhouseApi(client: client),
        feed: FakeFeed.new,
      ),
    );
    await _pump(tester);

    await tester.tap(find.byType(DropdownButton<String>).first);
    await _select(tester, 'Mode: Sprinkle');
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Could not update the pump mode'), findsOneWidget);
    expect(find.text('Mode: Drip'), findsOneWidget);
    expect(find.text('Mode: Sprinkle'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a live reading refreshes the dashboard conditions', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final feed = FakeFeed();
    await tester.pumpWidget(_app(responseFor, feed: () => feed));
    await _pump(tester);

    expect(find.text('42%'), findsOneWidget);
    expect(find.text('78%'), findsOneWidget);

    feed.publish(
      const SensorReading(
        moisture: 11,
        humidity: 22,
        recordedAt: null,
        temperature: 33,
        garbled: true,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('11%'), findsOneWidget);
    expect(find.text('22%'), findsOneWidget);
    expect(find.text('33 C'), findsOneWidget);
    expect(
      find.text('These readings are haunted, the numbers cannot be trusted'),
      findsOneWidget,
    );
    expect(find.text('42%'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the sensor trend filter downloads a series once and reuses it', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final requested = <Uri>[];
    final now = DateTime.now();
    final bucketStart = DateTime(now.year, now.month, now.day, now.hour);

    http.Response handler(Uri uri) {
      requested.add(uri);
      if (uri.path != '/sensor/data/') return responseFor(uri);
      if (uri.queryParameters['bucket'] != null) {
        return http.Response(
          '[{"start":"${bucketStart.toIso8601String()}",'
          '"moisture_level":41.5,"humidity":77.5,"temperature":23.25,'
          '"readings":2}]',
          200,
        );
      }
      return http.Response(
        '[{"id":1,"moisture_level":42,"humidity":78,"temperature":23.5,'
        '"recorded_at":"${now.toIso8601String()}","sensor_id":1,'
        '"garbled":false}]',
        200,
      );
    }

    await tester.pumpWidget(_app(handler));
    await _pump(tester);

    await tester.tap(find.text('Sensor Readings'));
    await tester.pumpAndSettle();

    final raw = requested.singleWhere(
      (uri) =>
          uri.path == '/sensor/data/' &&
          uri.queryParameters['bucket'] == null &&
          uri.queryParameters['limit'] == '60',
    );
    expect(raw.queryParameters, containsPair('offset', '0'));

    await tester.tap(find.text('Real-time').first);
    await _select(tester, 'Hours');

    final buckets = requested
        .where((uri) => uri.queryParameters['bucket'] == 'hour')
        .toList();
    expect(buckets, hasLength(1));
    expect(buckets.single.queryParameters, {'bucket': 'hour', 'limit': '25'});
    expect(find.text('Hours'), findsOneWidget);

    // The second chart of the same range uses the series fetched above.
    await tester.tap(find.text('Real-time'));
    await _select(tester, 'Hours');

    expect(
      requested.where((uri) => uri.queryParameters['bucket'] == 'hour'),
      hasLength(1),
    );
    expect(find.text('Hours'), findsNWidgets(2));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  test(
    'the readings are asked for as a window and returned oldest first',
    () async {
      final requested = <Uri>[];
      final since = DateTime(2026, 10, 1, 9);
      final until = DateTime(2026, 10, 1, 13);
      final client = MockClient((request) async {
        requested.add(request.url);
        return http.Response(
          '[{"id":2,"moisture_level":20,"humidity":70,"temperature":23.5,'
          '"recorded_at":"2026-10-01T12:00:00","sensor_id":1,"garbled":false},'
          '{"id":1,"moisture_level":10,"humidity":60,"temperature":22.5,'
          '"recorded_at":"2026-10-01T10:00:00","sensor_id":1,"garbled":false}]',
          200,
        );
      });
      final api = GreenhouseApi(client: client);

      final readings = await api.loadSensorReadings(
        limit: 5,
        offset: 2,
        since: since,
        until: until,
      );

      expect(requested.single.path, '/sensor/data/');
      expect(requested.single.queryParameters, {
        'limit': '5',
        'offset': '2',
        'since': since.toIso8601String(),
        'until': until.toIso8601String(),
      });
      expect(readings.map((reading) => reading.moisture), [10, 20]);
      expect(readings.last.recordedAt, DateTime(2026, 10, 1, 12));
    },
  );

  test('every chart range asks for its unit and one extra bucket', () async {
    final requested = <Uri>[];
    final client = MockClient((request) async {
      requested.add(request.url);
      return http.Response('[]', 200);
    });
    final api = GreenhouseApi(client: client);

    for (final range in TimeRange.values) {
      if (range.unit == null) continue;
      await api.loadSensorBuckets(range);

      expect(requested.last.path, '/sensor/data/');
      expect(requested.last.queryParameters, {
        'bucket': range.unit,
        'limit': '${range.slots + 1}',
      });
    }

    expect(requested, hasLength(TimeRange.values.length - 1));
    await expectLater(
      api.loadSensorBuckets(TimeRange.realTime),
      throwsArgumentError,
    );

    api.dispose();
  });
}
