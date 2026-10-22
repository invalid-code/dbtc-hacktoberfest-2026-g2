import 'package:frontend/core/widgets/chart_painter.dart';

/// Draws a line chart by hand, the value of the points is written above them.
class LineChartPainter extends ChartPainter {
  const LineChartPainter({
    required super.buckets,
    super.maxValue,
    super.valueSuffix,
  }) : super(showValues: true);
}
