import 'package:flutter/material.dart';

import 'package:frontend/core/models/chart_series.dart';
import 'package:frontend/core/widgets/formatting.dart';

/// Draws a line chart by hand, there is no charting library.
///
/// The x axis is labelled with the labels of the buckets. The values are
/// scaled to `maxValue`, a value of `maxValue` fills the height of the chart.
class ChartPainter extends CustomPainter {
  const ChartPainter({
    required this.buckets,
    this.maxValue,
    this.valueSuffix = '',
    this.showValues = false,
  });

  /// The buckets of the graph, oldest first.
  final List<ChartBucket> buckets;

  /// The value that fills the height of the chart, the values are drawn as
  /// they are when it is not set.
  final double? maxValue;

  /// The text written after the value of a point.
  final String valueSuffix;

  /// Whether the value of the points is written above them.
  final bool showValues;

  @override
  void paint(Canvas canvas, Size size) {
    if (buckets.length < 2) {
      _paintMessage(canvas, size, 'Not enough data');
      return;
    }

    const left = 38.0;
    const top = 18.0;
    final chart = Rect.fromLTWH(
      left,
      top,
      size.width - left - 12,
      size.height - 48,
    );

    _paintGrid(canvas, chart);
    _paintLine(canvas, chart);
    _paintAxis(canvas, chart, size);
    if (showValues) _paintValues(canvas, chart, size);
  }

  /// The horizontal lines of the grid and the vertical ones of the labels.
  void _paintGrid(Canvas canvas, Rect chart) {
    final grid = Paint()
      ..color = const Color(0xffb8b8b8)
      ..strokeWidth = 1;
    for (var i = 0; i < 8; i++) {
      final y = chart.top + chart.height * i / 7;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), grid);
    }
    final vertical = Paint()
      ..color = const Color(0xffe0e0e0)
      ..strokeWidth = 1;
    for (final index in _labelIndices(chart)) {
      final x = _xOf(chart, index);
      canvas.drawLine(Offset(x, chart.top), Offset(x, chart.bottom), vertical);
    }
  }

  /// The line through the values of the buckets.
  void _paintLine(Canvas canvas, Rect chart) {
    final line = Paint()
      ..color = const Color(0xff007300)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    final path = Path();
    for (var i = 0; i < buckets.length; i++) {
      final point = Offset(_xOf(chart, i), _yOf(chart, buckets[i].value));
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(path, line);
  }

  /// The labels of the buckets on the x axis.
  void _paintAxis(Canvas canvas, Rect chart, Size size) {
    final text = TextPainter(textDirection: TextDirection.ltr);
    for (final index in _labelIndices(chart)) {
      text.text = TextSpan(
        text: buckets[index].label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: Color(0xff424242),
        ),
      );
      text.layout();
      text.paint(
        canvas,
        Offset(
          _clamp(_xOf(chart, index) - text.width / 2, 0, size.width - text.width),
          chart.bottom + 12,
        ),
      );
    }
  }

  /// The value of the points written above them.
  void _paintValues(Canvas canvas, Rect chart, Size size) {
    final text = TextPainter(textDirection: TextDirection.ltr);
    // Only a few points are labelled, they would overlap otherwise.
    final step = (buckets.length / 12).ceil();
    for (var i = 0; i < buckets.length; i += step) {
      final bucket = buckets[i];
      text.text = TextSpan(
        text: '${formatNumber(bucket.value)}$valueSuffix',
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: Color(0xff424242),
        ),
      );
      text.layout();
      text.paint(
        canvas,
        Offset(
          _clamp(_xOf(chart, i) - text.width / 2, 0, size.width - text.width),
          _yOf(chart, bucket.value) - text.height - 6,
        ),
      );
    }
  }

  /// The message shown when the graph has nothing to draw.
  void _paintMessage(Canvas canvas, Size size, String message) {
    final text = TextPainter(
      text: TextSpan(
        text: message,
        style: const TextStyle(fontSize: 13, color: Colors.black54),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(
      canvas,
      Offset((size.width - text.width) / 2, (size.height - text.height) / 2),
    );
  }

  /// The buckets whose label is drawn, spread over the width of the chart.
  List<int> _labelIndices(Rect chart) {
    final count = buckets.length;
    final maxLabels = (chart.width / 60).floor().clamp(2, count);
    return [
      for (var i = 0; i < maxLabels; i++)
        ((count - 1) * i / (maxLabels - 1)).round(),
    ];
  }

  /// The x of a bucket on the chart.
  double _xOf(Rect chart, int index) =>
      chart.left + chart.width * index / (buckets.length - 1);

  /// The y of a value on the chart.
  double _yOf(Rect chart, double value) =>
      chart.bottom - chart.height * _scale(value);

  /// The value as a part of the height of the chart.
  double _scale(double value) {
    final max = maxValue;
    if (max == null || max <= 0) return value.clamp(0.0, 1.0);
    return (value / max).clamp(0.0, 1.0);
  }

  /// Keeps the text inside the canvas.
  double _clamp(double value, double min, double max) =>
      value.clamp(min, max).toDouble();

  @override
  bool shouldRepaint(covariant ChartPainter oldDelegate) =>
      oldDelegate.runtimeType != runtimeType ||
      oldDelegate.buckets != buckets ||
      oldDelegate.maxValue != maxValue ||
      oldDelegate.valueSuffix != valueSuffix ||
      oldDelegate.showValues != showValues;
}
