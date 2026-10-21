import 'package:flutter/material.dart';

/// Draws the monthly water usage chart by hand, there is no charting library.
class ChartPainter extends CustomPainter {
  const ChartPainter({this.values});

  final List<double>? values;

  /// The placeholder series drawn while there is no data yet.
  static const fallbackValues = [
    0.72,
    0.51,
    0.62,
    0.43,
    0.8,
    0.55,
    0.69,
    0.48,
    0.58,
    0.4,
    0.63,
    0.52,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    const left = 38.0;
    const top = 18.0;
    final chart = Rect.fromLTWH(
      left,
      top,
      size.width - left - 12,
      size.height - 48,
    );
    final grid = Paint()
      ..color = const Color(0xffb8b8b8)
      ..strokeWidth = 1;
    for (var i = 0; i < 8; i++) {
      final y = chart.top + chart.height * i / 7;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), grid);
    }
    for (var i = 0; i < 12; i++) {
      final x = chart.left + chart.width * i / 11;
      canvas.drawLine(
        Offset(x, chart.top),
        Offset(x, chart.bottom),
        grid..color = const Color(0xffe0e0e0),
      );
    }
    final line = Paint()
      ..color = const Color(0xff007300)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    final data = values ?? fallbackValues;
    final path = Path();
    for (var i = 0; i < data.length; i++) {
      final point = Offset(
        chart.left + chart.width * i / (data.length - 1),
        chart.bottom - chart.height * data[i],
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(path, line);
    final text = TextPainter(textDirection: TextDirection.ltr);
    const months = [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC',
    ];
    for (var i = 0; i < months.length; i++) {
      text.text = TextSpan(
        text: months[i],
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
          chart.left + chart.width * i / 11 - text.width / 2,
          chart.bottom + 12,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant ChartPainter oldDelegate) =>
      oldDelegate.values != values;
}
