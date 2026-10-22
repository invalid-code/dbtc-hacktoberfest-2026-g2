import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:frontend/core/models/chart_series.dart';
import 'package:frontend/core/models/time_range.dart';
import 'package:frontend/core/widgets/chart_painter.dart';

/// The width of a unit of the range on the x axis.
const _unitWidth = 50.0;

/// A line chart that fits the height of its parent and scrolls sideways.
///
/// Every bucket of the range gets [_unitWidth] pixels, so a range with more
/// units than the screen can show is read by scrolling instead of squeezing
/// the points together. The newest data is shown first.
class ScrollableChart extends StatefulWidget {
  const ScrollableChart({
    super.key,
    required this.buckets,
    required this.range,
    this.maxValue,
    this.valueSuffix = '',
    this.showValues = false,
  });

  /// The buckets of the graph, oldest first.
  final List<ChartBucket> buckets;

  /// The range the buckets were grouped by, it sets the width of the axis.
  final TimeRange range;

  /// The value that fills the height of the chart.
  final double? maxValue;

  /// The text written after the value of a point.
  final String valueSuffix;

  /// Whether the value of the points is written above them.
  final bool showValues;

  @override
  State<ScrollableChart> createState() => _ScrollableChartState();
}

class _ScrollableChartState extends State<ScrollableChart> {
  final _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    _jumpToEnd();
  }

  @override
  void didUpdateWidget(ScrollableChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    final atEnd =
        !_controller.hasClients || _controller.position.extentAfter < 1;
    if (oldWidget.range != widget.range || atEnd) _jumpToEnd();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Shows the newest data after the frame that may have made the graph
  /// longer.
  void _jumpToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      _controller.jumpTo(_controller.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final units = widget.range == TimeRange.realTime
            ? widget.buckets.length
            : widget.range.slots;
        // A graph with nothing to draw keeps the width of its parent, the
        // message of the painter would sit off screen otherwise.
        final width = widget.buckets.length < 2
            ? constraints.maxWidth
            : math.max(constraints.maxWidth, units * _unitWidth);
        final scrollable = width > constraints.maxWidth;
        return ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            dragDevices: const {
              PointerDeviceKind.touch,
              PointerDeviceKind.mouse,
              PointerDeviceKind.stylus,
              PointerDeviceKind.trackpad,
            },
          ),
          child: Scrollbar(
            controller: _controller,
            thumbVisibility: scrollable,
            thickness: 3,
            child: SingleChildScrollView(
              controller: _controller,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: width,
                height: constraints.maxHeight,
                child: CustomPaint(
                  painter: ChartPainter(
                    buckets: widget.buckets,
                    maxValue: widget.maxValue,
                    valueSuffix: widget.valueSuffix,
                    showValues: widget.showValues,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
