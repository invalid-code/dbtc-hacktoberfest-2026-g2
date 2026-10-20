import 'package:flutter/material.dart';

class SortMenu extends StatelessWidget {
  const SortMenu({super.key, required this.onChanged});

  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<bool>(
      tooltip: 'Sort by timestamp',
      onSelected: onChanged,
      itemBuilder: (_) => const [
        PopupMenuItem(value: true, child: Text('Newest first')),
        PopupMenuItem(value: false, child: Text('Oldest first')),
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
            Text(
              'Timestamp',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const Icon(Icons.arrow_drop_down, size: 20),
          ],
        ),
      ),
    );
  }
}
