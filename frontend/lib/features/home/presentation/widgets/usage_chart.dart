import 'package:flutter/material.dart';

import 'package:frontend/core/widgets/chart_painter.dart';
import 'package:frontend/core/widgets/panel.dart';

class UsageChart extends StatelessWidget {
  const UsageChart({super.key, this.monthlyUsage, this.failed = false});

  final List<double>? monthlyUsage;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    return Panel(
      title: 'Water Usage History',
      child: SizedBox(
        height: panelContentHeight,
        child: failed
            ? const Center(
                child: Text(
                  'Could not load water usage',
                  style: TextStyle(color: Colors.black54),
                ),
              )
            : monthlyUsage == null
            ? const Center(child: CircularProgressIndicator())
            : monthlyUsage!.isEmpty
            ? const Center(
                child: Text(
                  'No water usage recorded yet',
                  style: TextStyle(color: Colors.black54),
                ),
              )
            : CustomPaint(
                painter: ChartPainter(values: monthlyUsage),
                child: const SizedBox.expand(),
              ),
      ),
    );
  }
}
