import 'package:flutter/material.dart';

import 'package:frontend/core/widgets/formatting.dart';
import 'package:frontend/core/widgets/panel.dart';
import 'package:frontend/features/history/data/pump_history_entry.dart';

/// The history panel, the entries are split into today and yesterday.
class HistorySummary extends StatelessWidget {
  const HistorySummary({super.key, this.history, this.failed = false});

  final List<PumpHistoryEntry>? history;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    return Panel(
      title: 'History Summary',
      child: SizedBox(
        height: panelContentHeight,
        child: failed
            ? const Center(
                child: Text(
                  'Could not load history',
                  style: TextStyle(color: Colors.black54),
                ),
              )
            : history == null
            ? const Center(child: CircularProgressIndicator())
            : history!.isEmpty
            ? const Center(
                child: Text(
                  'No water usage recorded yet',
                  style: TextStyle(color: Colors.black54),
                ),
              )
            : SingleChildScrollView(child: _summary(history!)),
      ),
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
