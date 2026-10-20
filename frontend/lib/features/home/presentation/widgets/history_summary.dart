import 'package:flutter/material.dart';

import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/widgets/formatting.dart';
import 'package:frontend/core/widgets/panel.dart';
import 'package:frontend/features/history/data/pump_history_entry.dart';

class HistorySummary extends StatefulWidget {
  const HistorySummary({super.key});

  @override
  State<HistorySummary> createState() => _HistorySummaryState();
}

class _HistorySummaryState extends State<HistorySummary> {
  final api = GreenhouseApi();
  List<PumpHistoryEntry>? history;
  bool failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final entries = await api.loadPumpHistory();
      if (mounted) setState(() => history = entries);
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  @override
  void dispose() {
    api.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = history;
    return Panel(
      title: 'History Summary',
      child: failed
          ? const Text(
              'Could not load history',
              style: TextStyle(color: Colors.black54),
            )
          : entries == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: CircularProgressIndicator(),
              ),
            )
          : _summary(entries),
    );
  }

  Widget _summary(List<PumpHistoryEntry> entries) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    bool sameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;

    bool onDay(PumpHistoryEntry entry, DateTime day) =>
        entry.recordedAt != null && sameDay(entry.recordedAt!, day);

    final todayEntries = entries.where((e) => onDay(e, today)).toList();
    final yesterdayEntries = entries.where((e) => onDay(e, yesterday)).toList();

    if (entries.isEmpty) {
      return const SizedBox(
        height: 340,
        child: Center(
          child: Text(
            'No water usage recorded yet',
            style: TextStyle(color: Colors.black54),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Today',
          style: TextStyle(fontSize: 17, color: Colors.black54),
        ),
        const SizedBox(height: 12),
        if (todayEntries.isEmpty)
          const Text('No water usage', style: TextStyle(color: Colors.black54))
        else
          ...todayEntries.map(_summaryLine),
        const SizedBox(height: 22),
        const Divider(),
        const SizedBox(height: 12),
        const Text(
          'Yesterday',
          style: TextStyle(fontSize: 17, color: Colors.black54),
        ),
        const SizedBox(height: 12),
        if (yesterdayEntries.isEmpty)
          const Text('No water usage', style: TextStyle(color: Colors.black54))
        else
          ...yesterdayEntries.map(_summaryLine),
      ],
    );
  }

  Widget _summaryLine(PumpHistoryEntry entry) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      '${pumpLabel(entry)}: ${formatLiters(entry.liters)} at '
      '${formatTime(entry.recordedAt)}',
    ),
  );
}
