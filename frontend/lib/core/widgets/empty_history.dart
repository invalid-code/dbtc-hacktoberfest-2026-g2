import 'package:flutter/material.dart';

/// The empty state shown when there is no watering history.
class EmptyHistory extends StatelessWidget {
  const EmptyHistory({super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: const [
        Icon(Icons.layers_clear_outlined, size: 34, color: Colors.black54),
        SizedBox(height: 8),
        Text('History Clear!', style: TextStyle(color: Colors.black54)),
      ],
    ),
  );
}
