import 'package:flutter/material.dart';

/// Height of the body of a dashboard panel, so panels keep the same size
/// whatever they show.
const panelContentHeight = 340.0;

/// The card every dashboard section is built with.
///
/// `fillHeight` lets the body grow to fill the panel, the `actions` are
/// rendered next to the title in the header.
class Panel extends StatelessWidget {
  const Panel({super.key, 
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
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 32),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ...?actions,
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (fillHeight) Expanded(child: content) else content,
        ],
      ),
    );
  }
}
