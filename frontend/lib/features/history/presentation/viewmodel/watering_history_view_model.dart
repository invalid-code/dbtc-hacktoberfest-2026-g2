import 'package:flutter/foundation.dart';

import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/features/history/data/pump_history_entry.dart';

class WateringHistoryViewModel extends ChangeNotifier {
  WateringHistoryViewModel({GreenhouseApi? api})
    : _api = api ?? GreenhouseApi();

  final GreenhouseApi _api;

  List<PumpHistoryEntry>? history;
  bool failed = false;
  bool newestFirst = true;

  List<PumpHistoryEntry>? get sortedHistory {
    final entries = history;
    if (entries == null) return null;
    return List<PumpHistoryEntry>.from(entries)
      ..sort(
        (a, b) => newestFirst
            ? (b.recordedAt ?? DateTime(0)).compareTo(
                a.recordedAt ?? DateTime(0),
              )
            : (a.recordedAt ?? DateTime(0)).compareTo(
                b.recordedAt ?? DateTime(0),
              ),
      );
  }

  void start() => _load();

  Future<void> _load() async {
    try {
      history = await _api.loadPumpHistory();
    } catch (_) {
      failed = true;
    }
    notifyListeners();
  }

  void setNewestFirst(bool value) {
    newestFirst = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }
}
