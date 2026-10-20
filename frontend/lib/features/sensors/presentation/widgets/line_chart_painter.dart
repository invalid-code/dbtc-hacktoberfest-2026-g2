import 'package:flutter/material.dart';

class LineChartPainter extends CustomPainter {
  const LineChartPainter({required this.values});

  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) {
      final text = TextPainter(
        text: const TextSpan(
          text: 'Not enough data',
          style: TextStyle(fontSize: 13, color: Colors.black54),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(
        canvas,
        Offset((size.width - text.width) / 2, (size.height - text.height) / 2),
      );
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
    final grid = Paint()
      ..color = const Color(0xffb8b8b8)
      ..strokeWidth = 1;
    for (var i = 0; i < 8; i++) {
      final y = chart.top + chart.height * i / 7;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), grid);
    }

    final line = Paint()
      ..color = const Color(0xff007300)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final point = Offset(
        chart.left + chart.width * i / (values.length - 1),
        chart.bottom - chart.height * values[i],
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(path, line);

    final text = TextPainter(textDirection: TextDirection.ltr);
    for (var i = 0; i < values.length; i++) {
      text.text = TextSpan(
        text: '${(values[i] * 100).round()}',
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
          chart.left + chart.width * i / (values.length - 1) - text.width / 2,
          chart.bottom - chart.height * values[i] - text.height - 6,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant LineChartPainter oldDelegate) =>
      oldDelegate.values != values;
}
