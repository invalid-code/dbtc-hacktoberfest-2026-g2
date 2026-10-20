import 'package:flutter/material.dart';

class Panel extends StatelessWidget {
  const Panel({
    required this.title,
    required this.child,
    this.fillHeight = false,
    this.actions,
  });

  final String title;
  final Widget child;
  final bool fillHeight;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xffccdec3),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              ...?actions,
            ],
          ),
          const SizedBox(height: 14),
          if (fillHeight) Expanded(child: content) else content,
        ],
      ),
    );
  }
}
