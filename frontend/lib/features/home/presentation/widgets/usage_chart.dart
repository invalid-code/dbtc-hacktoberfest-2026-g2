import 'package:flutter/material.dart';

import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/widgets/chart_painter.dart';
import 'package:frontend/core/widgets/panel.dart';
import 'package:frontend/features/history/data/pump_history_entry.dart';

class UsageChart extends StatefulWidget {
  const UsageChart({super.key});

  @override
  State<UsageChart> createState() => _UsageChartState();
}

class _UsageChartState extends State<UsageChart> {
  final api = GreenhouseApi();
  List<double>? monthlyUsage;
  bool failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final entries = await api.loadPumpHistory();
      if (mounted) {
        setState(
          () => monthlyUsage = entries.isEmpty
              ? const []
              : _monthlyUsage(entries),
        );
      }
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  List<double> _monthlyUsage(List<PumpHistoryEntry> entries) {
    final year = DateTime.now().year;
    final totals = List<double>.filled(12, 0);
    for (final entry in entries) {
      final at = entry.recordedAt;
      if (at == null || at.year != year) continue;
      totals[at.month - 1] += entry.liters;
    }
    final max = totals.reduce((a, b) => a > b ? a : b);
    if (max <= 0) return totals;
    return totals.map((value) => value / max).toList();
  }

  @override
  void dispose() {
    api.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final usage = monthlyUsage;
    return Panel(
      title: 'Water Usage History',
      child: SizedBox(
        height: 340,
        child: failed
            ? const Center(
                child: Text(
                  'Could not load water usage',
                  style: TextStyle(color: Colors.black54),
                ),
              )
            : usage == null
            ? const Center(child: CircularProgressIndicator())
            : usage.isEmpty
            ? const Center(
                child: Text(
                  'No water usage recorded yet',
                  style: TextStyle(color: Colors.black54),
                ),
              )
            : CustomPaint(
                painter: ChartPainter(values: usage),
                child: const SizedBox.expand(),
              ),
      ),
    );
  }
}
