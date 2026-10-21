import 'package:flutter/material.dart';

import 'package:frontend/core/widgets/panel.dart';
import 'package:frontend/model/alert.dart';

const _spookyColor = Color(0xff6a1b9a);

/// The alerts panel of the dashboard.
class AlertsCard extends StatelessWidget {
  const AlertsCard({super.key, this.alerts, this.failed = false});

  final List<Alert>? alerts;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    return Panel(
      title: 'Alerts',
      child: SizedBox(
        height: panelContentHeight,
        child: failed
            ? const Center(
                child: Text(
                  'Could not load alerts',
                  style: TextStyle(color: Colors.black54),
                ),
              )
            : alerts == null
            ? const Center(child: CircularProgressIndicator())
            : alerts!.isEmpty
            ? const Center(
                child: Text(
                  'No alerts',
                  style: TextStyle(color: Colors.black54),
                ),
              )
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < alerts!.length; i++) ...[
                      if (i > 0) const SizedBox(height: 12),
                      _AlertMessage(alert: alerts![i]),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}

/// One alert, the severity decides the style: `spooky` is purple with a
/// sparkle icon, `critical` is dark red and anything else is muted.
class _AlertMessage extends StatelessWidget {
  const _AlertMessage({required this.alert});

  final Alert alert;

  @override
  Widget build(BuildContext context) {
    if (alert.severity == 'spooky') {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.auto_awesome, size: 18, color: _spookyColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              alert.message,
              style: const TextStyle(
                color: _spookyColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      );
    }

    return Text(
      alert.message,
      style: alert.severity == 'critical'
          ? const TextStyle(
              color: Color(0xff760202),
              fontWeight: FontWeight.w600,
            )
          : const TextStyle(color: Colors.black54),
    );
  }
}
