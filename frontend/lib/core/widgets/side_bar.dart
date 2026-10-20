import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/router/routes.dart';

class SideBar extends StatelessWidget {
  const SideBar({super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: 194,
    color: Colors.white,
    padding: const EdgeInsets.fromLTRB(18, 30, 18, 28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'TITO MERMANO',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 58),
        InkWell(
          onTap: () => context.go(AppRoutes.home),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
            child: Row(
              children: [
                Icon(Icons.grid_view_rounded),
                SizedBox(width: 12),
                const Flexible(
                  child: Text("Dashboard", overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        InkWell(
          onTap: () => context.go(AppRoutes.wateringHistory),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
            child: Row(
              children: [
                Icon(Icons.eco_outlined),
                SizedBox(width: 12),
                const Flexible(
                  child: Text(
                    "Watering History",
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        InkWell(
          onTap: () => context.go(AppRoutes.sensorReading),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
            child: Row(
              children: [
                Icon(Icons.bar_chart_rounded),
                SizedBox(width: 12),
                const Flexible(
                  child: Text(
                    "Sensor Readings",
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
