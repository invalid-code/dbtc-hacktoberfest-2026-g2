import 'package:flutter/material.dart';

import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/widgets/panel.dart';
import 'package:frontend/model/alert.dart';

class AlertsCard extends StatefulWidget {
  const AlertsCard({super.key});

  @override
  State<AlertsCard> createState() => _AlertsCardState();
}

class _AlertsCardState extends State<AlertsCard> {
  final api = GreenhouseApi();
  List<Alert>? alerts;
  bool failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await api.loadAlerts();
      if (mounted) setState(() => alerts = items);
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  @override
  void dispose() {
    api.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = alerts;
    return Panel(
      title: 'Alerts',
      child: failed
          ? const Text(
              'Could not load alerts',
              style: TextStyle(color: Colors.black54),
            )
          : items == null
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
          ? const Text('No alerts', style: TextStyle(color: Colors.black54))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const SizedBox(height: 12),
                  Text(
                    items[i].message,
                    style: items[i].severity == 'critical'
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
