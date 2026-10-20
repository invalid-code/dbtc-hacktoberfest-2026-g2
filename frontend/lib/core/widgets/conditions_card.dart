import 'package:flutter/material.dart';

import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/widgets/formatting.dart';

class ConditionsCard extends StatefulWidget {
  const ConditionsCard({super.key, this.snapshot});

  final GreenhouseSnapshot? snapshot;

  @override
  State<ConditionsCard> createState() => _ConditionsCardState();
}

class _ConditionsCardState extends State<ConditionsCard> {
  final api = GreenhouseApi();
  double? todayUsageLiters;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final liters = await api.loadTodayWaterUsage();
      if (mounted) setState(() => todayUsageLiters = liters);
    } catch (_) {}
  }

  @override
  void dispose() {
    api.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    final usage = todayUsageLiters;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xffccdec3),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Current Conditions',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              const Icon(Icons.info_outline, size: 20, color: Colors.black54),
              const SizedBox(width: 8),
              const Flexible(
                child: Text(
                  'Sensor readings represent greenhouse metrics',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.black54),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) => GridView.count(
              crossAxisCount: constraints.maxWidth > 700
                  ? 4
                  : constraints.maxWidth > 420
                  ? 2
                  : 1,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              childAspectRatio: 1.5,
              children: [
                _MetricCard(
                  label: "Today's water usage",
                  value: usage == null ? '—' : formatLiters(usage),
                ),
                _MetricCard(
                  label: 'Soil Moisture',
                  value: '${snapshot?.sensor?.moisture ?? 45}%',
                ),
                _MetricCard(
                  label: 'Humidity',
                  value: '${snapshot?.sensor?.waterLevel ?? 45}%',
                ),
                _MetricCard(
                  label: 'Temperature',
                  value: _formatTemperature(snapshot?.sensor?.temperature),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              'Last updated · ${formatRecordedAt(snapshot?.sensor?.recordedAt)}',
              style: const TextStyle(color: Colors.black54, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15),
        ),
        const SizedBox(height: 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}

String _formatTemperature(double? temperature) {
  if (temperature == null) return '—';
  final value = temperature == temperature.roundToDouble()
      ? temperature.toInt()
      : temperature;
  return '$value C';
}
