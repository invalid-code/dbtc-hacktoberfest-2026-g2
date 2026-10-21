import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/features/history/presentation/viewmodel/watering_history_view_model.dart';
import 'package:frontend/features/home/presentation/viewmodel/home_view_model.dart';
import 'package:frontend/features/sensors/data/sensor_reading.dart';
import 'package:frontend/features/sensors/presentation/viewmodel/sensor_readings_view_model.dart';

import 'support/fakes.dart';

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
      expect(viewModel.monthlyUsage, isNotEmpty);

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
        api: fakeApi((path) {
          if (path == '/sensor/data/') return failingResponseFor(path);
          return responseFor(path);
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

    test('the monthly usage is normalised per month', () async {
      final viewModel = HomeViewModel(
        api: fakeApi(responseFor),
        feed: FakeFeed(),
      )..start();

      await waitFor(() => viewModel.monthlyUsage != null);

      final usage = viewModel.monthlyUsage!;
      expect(usage.length, 12);
      expect(usage.reduce((a, b) => a > b ? a : b), 1);

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
      final viewModel = SensorReadingsViewModel(api: fakeApi(responseFor))
        ..start();

      await waitFor(() => viewModel.readings != null);

      expect(viewModel.readings?.length, 1);
      expect(viewModel.readings?.first.humidity, 78);
      expect(viewModel.failed, isFalse);

      viewModel.dispose();
    });

    test('reports a failure when the API does not answer', () async {
      final viewModel = SensorReadingsViewModel(api: fakeApi(failingResponseFor))
        ..start();

      await waitFor(() => viewModel.failed);

      expect(viewModel.failed, isTrue);
      expect(viewModel.readings, isNull);

      viewModel.dispose();
    });
  });
}
