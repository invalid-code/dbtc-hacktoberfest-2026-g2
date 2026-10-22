import 'package:flutter/material.dart';

import 'package:frontend/core/models/time_range.dart';

/// The time range filter of a graph, rendered as a chip in the panel header.
///
/// The chip shows the unit the graph is filtered by, the menu holds every
/// unit.
class TimeRangeFilter extends StatelessWidget {
  const TimeRangeFilter({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final TimeRange value;
  final ValueChanged<TimeRange> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<TimeRange>(
      tooltip: 'Filter by time range',
      onSelected: onChanged,
      itemBuilder: (_) => [
        for (final range in TimeRange.values)
          PopupMenuItem(value: range, child: Text(range.label)),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xffd6d6d6)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.schedule, size: 16),
            const SizedBox(width: 6),
            Text(
              value.label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const Icon(Icons.arrow_drop_down, size: 20),
          ],
        ),
      ),
    );
  }
}
