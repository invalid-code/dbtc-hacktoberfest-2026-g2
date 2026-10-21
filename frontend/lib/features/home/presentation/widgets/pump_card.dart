import 'package:flutter/material.dart';

import 'package:frontend/model/pump_info.dart';

/// One card per pump, with the mode dropdown and the start/stop button.
class PumpCard extends StatefulWidget {
  const PumpCard({
    super.key,
    required this.name,
    required this.pumpId,
    this.initialMode,
    this.onModeChanged,
  });

  final String name;
  final int pumpId;
  final int? initialMode;
  final Future<void> Function(int pumpId, int mode)? onModeChanged;

  @override
  State<PumpCard> createState() => _PumpCardState();
}

class _PumpCardState extends State<PumpCard> {
  bool running = true;
  late String mode;

  @override
  void initState() {
    super.initState();
    mode = pumpModeLabel(widget.initialMode);
  }

  @override
  void didUpdateWidget(PumpCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = pumpModeLabel(widget.initialMode);
    if (next != mode) setState(() => mode = next);
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.name,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Text(
          running ? 'Running' : 'Stopped',
          style: const TextStyle(fontSize: 16),
        ),
        const SizedBox(height: 6),
        DropdownButton<String>(
          value: mode,
          isDense: true,
          isExpanded: true,
          items: pumpModeLabels
              .map(
                (value) =>
                    DropdownMenuItem(value: value, child: Text('Mode: $value')),
              )
              .toList(),
          onChanged: _changeMode,
        ),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: running
                  ? const Color(0xff760202)
                  : const Color(0xff384b2c),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(5),
              ),
            ),
            // The button only toggles a local flag, it never reaches the API.
            onPressed: () => setState(() => running = !running),
            child: Text(running ? 'Stop' : 'Start'),
          ),
        ),
      ],
    ),
  );

  /// The change is optimistic: the dropdown moves first and rolls back with a
  /// snack bar when the request fails.
  Future<void> _changeMode(String? value) async {
    if (value == null || value == mode) return;
    final previous = mode;
    setState(() => mode = value);
    try {
      await widget.onModeChanged?.call(
        widget.pumpId,
        pumpModeLabels.indexOf(value),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => mode = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update the pump mode')),
      );
    }
  }
}
