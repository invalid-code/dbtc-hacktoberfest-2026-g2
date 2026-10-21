import 'package:flutter/material.dart';

import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/widgets/formatting.dart';

/// The "Current Conditions" panel: today's water usage, soil moisture,
/// humidity and temperature.
class ConditionsCard extends StatelessWidget {
  const ConditionsCard({
    super.key,
    this.snapshot,
    this.todayUsageLiters,
    this.failed = false,
  });

  final GreenhouseSnapshot? snapshot;
  final double? todayUsageLiters;
  final bool failed;

  @override
  Widget build(BuildContext context) {
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
          // The microcontroller garbles the readings as a halloween easter egg,
          // the banner explains the numbers cannot be trusted.
          if (snapshot?.sensor?.garbled == true) ...[
            _SpookyBanner(),
            const SizedBox(height: 14),
          ],
          if (snapshot?.sensor == null)
            SizedBox(
              height: 180,
              child: Center(
                child: failed
                    ? const Text(
                        'Could not load sensor readings',
                        style: TextStyle(color: Colors.black54),
                      )
                    : const _EmptySensor(),
              ),
            )
          else
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
                    value: todayUsageLiters == null
                        ? '—'
                        : formatLiters(todayUsageLiters!),
                  ),
                  _MetricCard(
                    label: 'Soil Moisture',
                    value: '${snapshot?.sensor?.moisture ?? 45}%',
                  ),
                  _MetricCard(
                    label: 'Humidity',
                    value: '${snapshot?.sensor?.humidity ?? 45}%',
                  ),
                  _MetricCard(
                    label: 'Temperature',
                    value: _formatTemperature(snapshot?.sensor?.temperature),
                  ),
                ],
              ),
            ),
          if (snapshot?.sensor != null) ...[
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Last updated · ${formatRecordedAt(snapshot?.sensor?.recordedAt)}',
                style: const TextStyle(color: Colors.black54, fontSize: 13),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The banner shown when the latest reading is garbled.
class _SpookyBanner extends StatelessWidget {
  const _SpookyBanner();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0xffeee2f7),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: [
        const Icon(Icons.auto_awesome, size: 18, color: Color(0xff6a1b9a)),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            'These readings are haunted, the numbers cannot be trusted',
            style: TextStyle(color: Color(0xff6a1b9a)),
          ),
        ),
      ],
    ),
  );
}

class _EmptySensor extends StatelessWidget {
  const _EmptySensor();

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: const [
      Icon(Icons.sensors_off_outlined, size: 34, color: Colors.black54),
      SizedBox(height: 8),
      Text(
        'No sensor readings yet',
        style: TextStyle(color: Colors.black54),
      ),
    ],
  );
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
