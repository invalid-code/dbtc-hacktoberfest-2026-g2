import 'package:flutter/material.dart';

import 'package:frontend/core/models/chart_series.dart';
import 'package:frontend/core/models/time_range.dart';
import 'package:frontend/core/widgets/chart_painter.dart';
import 'package:frontend/core/widgets/panel.dart';
import 'package:frontend/core/widgets/time_range_filter.dart';

/// The panel with the water usage chart, filtered by a time unit.
class UsageChart extends StatelessWidget {
  const UsageChart({
    super.key,
    this.buckets,
    this.maxLiters = 1,
    this.range = TimeRange.month,
    this.onRangeChanged,
    this.failed = false,
  });

  /// The water usage of every unit of the range.
  final List<ChartBucket>? buckets;

  /// The amount of water that fills the chart.
  final double maxLiters;

  /// The time unit the chart is filtered by.
  final TimeRange range;

  /// Called when another time unit is picked.
  final ValueChanged<TimeRange>? onRangeChanged;

  final bool failed;

  @override
  Widget build(BuildContext context) {
    return Panel(
      title: 'Water Usage History',
      actions: [
        if (onRangeChanged != null)
          TimeRangeFilter(value: range, onChanged: onRangeChanged!),
      ],
      child: SizedBox(
        height: panelContentHeight,
        child: failed
            ? const Center(
                child: Text(
                  'Could not load water usage',
                  style: TextStyle(color: Colors.black54),
                ),
              )
            : buckets == null
            ? const Center(child: CircularProgressIndicator())
            : buckets!.isEmpty
            ? const Center(
                child: Text(
                  'No water usage recorded yet',
                  style: TextStyle(color: Colors.black54),
                ),
              )
            : CustomPaint(
                painter: ChartPainter(
                  buckets: buckets!,
                  maxValue: maxLiters,
                ),
                child: const SizedBox.expand(),
              ),
      ),
    );
  }
}
