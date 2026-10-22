import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:frontend/core/models/time_range.dart';
import 'package:frontend/features/history/presentation/viewmodel/watering_history_view_model.dart';
import 'package:frontend/features/home/presentation/viewmodel/home_view_model.dart';
import 'package:frontend/features/sensors/data/sensor_reading.dart';
import 'package:frontend/features/sensors/presentation/viewmodel/sensor_readings_view_model.dart';

import 'support/fakes.dart';

/// A history with a single watering at the given moment.
http.Response Function(Uri uri) historyAt(DateTime at) => (uri) {
  if (uri.path == '/pump/history/') {
    return http.Response(
      '[{"id":2,"liters":3.5,"recorded_at":"${at.toIso8601String()}","pump_id":1}]',
      200,
    );
  }
  return responseFor(uri);
};

/// A single reading taken at the given moment, raw or averaged.
http.Response Function(Uri uri) readingAt(DateTime at) => (uri) {
  if (uri.path != '/sensor/data/') return responseFor(uri);
  if (uri.queryParameters['bucket'] != null) {
    return http.Response(
      '[{"start":"${at.toIso8601String()}","moisture_level":42,'
      '"humidity":78,"temperature":23.5,"readings":1}]',
      200,
    );
  }
  return http.Response(
    '[{"id":1,"moisture_level":42,"humidity":78,"temperature":23.5,'
    '"recorded_at":"${at.toIso8601String()}","sensor_id":1,"garbled":false}]',
    200,
  );
};

void main() {
  group('HomeViewModel', () {
    test('loads the greenhouse state from the API', () async {
      final viewModel = HomeViewModel(
        api: fakeApi(responseFor),
        feed: FakeFeed(),
      )..start();

      await waitFor(() => viewModel.history != null);

      expect(viewModel.snapshot?.sensor?.moisture, 42);
      expect(viewModel.snapshot?.sensor?.humidity, 78);
      expect(viewModel.snapshot?.pumps.length, 3);
      expect(viewModel.snapshot?.pumps.first.mode, 2);
      expect(viewModel.todayUsageLiters, 12.5);
      expect(viewModel.alerts?.length, 1);
      expect(viewModel.history?.length, 1);
      expect(viewModel.usageBuckets, isNotEmpty);

      viewModel.dispose();
    });

    test('reports a failure for every endpoint that does not answer', () async {
      final viewModel = HomeViewModel(
        api: fakeApi(failingResponseFor),
        feed: FakeFeed(),
      )..start();

      await waitFor(() => viewModel.snapshotFailed);

      expect(viewModel.snapshotFailed, isTrue);
      expect(viewModel.usageFailed, isTrue);
      expect(viewModel.alertsFailed, isTrue);
      expect(viewModel.historyFailed, isTrue);
      expect(viewModel.snapshot, isNotNull);
      expect(viewModel.snapshot?.sensor, isNull);

      viewModel.dispose();
    });

    test('keeps the pumps when only the sensor readings fail', () async {
      final viewModel = HomeViewModel(
        api: fakeApi((uri) {
          if (uri.path == '/sensor/data/') return failingResponseFor(uri);
          return responseFor(uri);
        }),
        feed: FakeFeed(),
      )..start();

      await waitFor(() => viewModel.snapshot != null);

      expect(viewModel.snapshotFailed, isTrue);
      expect(viewModel.snapshot?.sensor, isNull);
      expect(viewModel.snapshot?.pumps.length, 3);

      viewModel.dispose();
    });

    test('a live reading replaces the sensor of the snapshot', () async {
      final feed = FakeFeed();
      final viewModel = HomeViewModel(
        api: fakeApi(responseFor),
        feed: feed,
      )..start();

      await waitFor(() => viewModel.snapshot != null);

      feed.publish(
        const SensorReading(
          moisture: 11,
          humidity: 22,
          recordedAt: null,
          temperature: 33,
        ),
      );
      await waitFor(() => viewModel.snapshot?.sensor?.moisture == 11);

      expect(viewModel.snapshot?.sensor?.humidity, 22);
      expect(viewModel.snapshot?.pumps.length, 3);

      viewModel.dispose();
    });

    test('updating a pump mode sends it to the API', () async {
      final calls = <String>[];
      final viewModel = HomeViewModel(
        api: fakeApi(responseFor, calls: calls),
        feed: FakeFeed(),
      )..start();

      await waitFor(() => viewModel.snapshot != null);

      await viewModel.updatePumpMode(1, 3);

      expect(calls, contains('PUT /pump/mode/'));
      expect(viewModel.snapshot?.pumps.first.mode, 3);
      expect(viewModel.pumpModeFor(0), 3);

      viewModel.dispose();
    });

    test('the usage is grouped into the buckets of the range', () async {
      final viewModel = HomeViewModel(
        api: fakeApi(
          historyAt(DateTime.now().subtract(const Duration(minutes: 5))),
        ),
        feed: FakeFeed(),
      )..start();

      await waitFor(() => viewModel.usageBuckets != null);

      final buckets = viewModel.usageBuckets!;
      expect(buckets.length, 1);
      expect(buckets.first.value, 3.5);
      expect(viewModel.usageMaxLiters, 3.5);

      viewModel.dispose();
    });

    test('the usage chart can be filtered by another time unit', () async {
      final viewModel = HomeViewModel(
        api: fakeApi(
          historyAt(DateTime.now().subtract(const Duration(minutes: 5))),
        ),
        feed: FakeFeed(),
      )..start();

      await waitFor(() => viewModel.usageBuckets != null);

      viewModel.setUsageRange(TimeRange.minute);

      expect(viewModel.usageRange, TimeRange.minute);
      expect(viewModel.usageBuckets, isNotEmpty);

      viewModel.setUsageRange(TimeRange.year);

      expect(viewModel.usageRange, TimeRange.year);
      expect(viewModel.usageBuckets, isNotEmpty);

      viewModel.dispose();
    });

    test('the usage outside of the range is left out', () async {
      final viewModel = HomeViewModel(
        api: fakeApi(
          historyAt(DateTime.now().subtract(const Duration(days: 3))),
        ),
        feed: FakeFeed(),
      )..start();

      await waitFor(() => viewModel.usageBuckets != null);
      expect(viewModel.usageBuckets, isNotEmpty);

      viewModel.setUsageRange(TimeRange.hour);

      expect(viewModel.usageBuckets, isEmpty);

      viewModel.dispose();
    });
  });

  group('WateringHistoryViewModel', () {
    test('loads the history and sorts it newest first', () async {
      final viewModel = WateringHistoryViewModel(api: fakeApi(responseFor))
        ..start();

      await waitFor(() => viewModel.history != null);

      expect(viewModel.history?.length, 1);
      expect(viewModel.sortedHistory?.first.liters, 3.5);
      expect(viewModel.failed, isFalse);

      viewModel.dispose();
    });

    test('the sort order can be flipped', () async {
      final viewModel = WateringHistoryViewModel(api: fakeApi(responseFor))
        ..start();

      await waitFor(() => viewModel.history != null);

      expect(viewModel.newestFirst, isTrue);

      viewModel.setNewestFirst(false);

      expect(viewModel.newestFirst, isFalse);
      expect(viewModel.sortedHistory, isNotEmpty);

      viewModel.dispose();
    });

    test('reports a failure when the API does not answer', () async {
      final viewModel = WateringHistoryViewModel(api: fakeApi(failingResponseFor))
        ..start();

      await waitFor(() => viewModel.failed);

      expect(viewModel.failed, isTrue);
      expect(viewModel.history, isNull);

      viewModel.dispose();
    });
  });

  group('SensorReadingsViewModel', () {
    test('loads the readings oldest first', () async {
      final viewModel = SensorReadingsViewModel(
        api: fakeApi(responseFor),
        feed: FakeFeed(),
      )..start();

      await waitFor(() => viewModel.readings != null);

      expect(viewModel.readings?.length, 1);
      expect(viewModel.readings?.first.humidity, 78);
      expect(viewModel.failed, isFalse);

      viewModel.dispose();
    });

    test('reports a failure when the API does not answer', () async {
      final viewModel = SensorReadingsViewModel(
        api: fakeApi(failingResponseFor),
        feed: FakeFeed(),
      )..start();

      await waitFor(() => viewModel.failed);

      expect(viewModel.failed, isTrue);
      expect(viewModel.readings, isNull);

      viewModel.dispose();
    });

    test('the trend charts can be filtered by another time unit', () async {
      final viewModel = SensorReadingsViewModel(
        api: fakeApi(
          readingAt(DateTime.now().subtract(const Duration(minutes: 5))),
        ),
        feed: FakeFeed(),
      )..start();

      await waitFor(() => viewModel.readings != null);

      expect(viewModel.temperatureRange, TimeRange.realTime);
      expect(viewModel.moistureRange, TimeRange.realTime);
      expect(viewModel.moistureBuckets.length, 1);
      expect(viewModel.moistureBuckets.first.value, 42);
      expect(viewModel.temperatureBuckets.first.value, 23.5);

      await viewModel.setMoistureRange(TimeRange.minute);

      expect(viewModel.moistureRange, TimeRange.minute);
      expect(viewModel.moistureBuckets.length, 1);

      viewModel.dispose();
    });

    test('the readings outside of the range are left out', () async {
      final viewModel = SensorReadingsViewModel(
        api: fakeApi(
          readingAt(DateTime.now().subtract(const Duration(days: 3))),
        ),
        feed: FakeFeed(),
      )..start();

      await waitFor(() => viewModel.readings != null);

      // The real time range keeps the latest readings, whatever their age.
      expect(viewModel.moistureBuckets.length, 1);

      await viewModel.setMoistureRange(TimeRange.hour);
      expect(viewModel.moistureBuckets, isEmpty);

      await viewModel.setMoistureRange(TimeRange.year);
      expect(viewModel.moistureBuckets.length, 1);
      expect(viewModel.moistureBuckets.first.value, 42);

      viewModel.dispose();
    });

    test('a live reading joins the graphs', () async {
      final feed = FakeFeed();
      final viewModel = SensorReadingsViewModel(
        api: fakeApi(
          readingAt(DateTime.now().subtract(const Duration(minutes: 5))),
        ),
        feed: feed,
      )..start();

      await waitFor(() => viewModel.readings != null);
      expect(viewModel.moistureBuckets.length, 1);

      feed.publish(
        SensorReading(
          moisture: 77,
          humidity: 60,
          recordedAt: DateTime.now(),
          temperature: 19,
        ),
      );
      await waitFor(() => viewModel.readings?.length == 2);

      expect(viewModel.moistureBuckets.length, 2);
      expect(viewModel.moistureBuckets.last.value, 77);
      expect(viewModel.temperatureBuckets.last.value, 19);

      viewModel.dispose();
    });
  });
}
