import 'package:flutter/material.dart';

import 'package:frontend/core/widgets/panel.dart';
import 'package:frontend/model/alert.dart';

class AlertsCard extends StatelessWidget {
  const AlertsCard({super.key, this.alerts, this.failed = false});

  final List<Alert>? alerts;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    return Panel(
      title: 'Alerts',
      child: failed
          ? const Text(
              'Could not load alerts',
              style: TextStyle(color: Colors.black54),
            )
          : alerts == null
          ? const Center(child: CircularProgressIndicator())
          : alerts!.isEmpty
          ? const Text('No alerts', style: TextStyle(color: Colors.black54))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < alerts!.length; i++) ...[
                  if (i > 0) const SizedBox(height: 12),
                  Text(
                    alerts![i].message,
                    style: alerts![i].severity == 'critical'
                        ? const TextStyle(
                            color: Color(0xff760202),
                            fontWeight: FontWeight.w600,
                          )
                        : const TextStyle(color: Colors.black54),
                  ),
                ],
              ],
            ),
    );
  }
}
