import 'package:flutter/material.dart';

class PumpCard extends StatefulWidget {
  const PumpCard({
    super.key,
    required this.name,
    required this.pumpId,
    this.onModeChanged,
  });

  final String name;
  final int pumpId;
  final Future<void> Function(int pumpId, int mode)? onModeChanged;

  @override
  State<PumpCard> createState() => _PumpCardState();
}

class _PumpCardState extends State<PumpCard> {
  bool running = true;
  String mode = 'Drip';

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
          items: ['Fast', 'Slow', 'Drip', 'Sprinkle']
              .map(
                (value) =>
                    DropdownMenuItem(value: value, child: Text('Mode: $value')),
              )
              .toList(),
          onChanged: (value) async {
            final next = value ?? mode;
            setState(() => mode = next);
            try {
              await widget.onModeChanged?.call(widget.pumpId, _modeValue(next));
            } catch (_) {}
          },
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
            onPressed: () => setState(() => running = !running),
            child: Text(running ? 'Stop' : 'Start'),
          ),
        ),
      ],
    ),
  );

  int _modeValue(String value) =>
      ['Fast', 'Slow', 'Drip', 'Sprinkle'].indexOf(value);
}
