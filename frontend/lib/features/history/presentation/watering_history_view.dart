import 'package:flutter/material.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/widgets/empty_history.dart';
import 'package:frontend/core/widgets/formatting.dart';
import 'package:frontend/core/widgets/panel.dart';
import 'package:frontend/core/widgets/side_bar.dart';
import 'package:frontend/core/widgets/sort_menu.dart';
import 'package:frontend/features/history/data/pump_history_entry.dart';

class WateringHistoryView extends StatefulWidget {
  const WateringHistoryView({super.key});

  @override
  State<WateringHistoryView> createState() => _WateringHistoryViewState();
}

class _WateringHistoryViewState extends State<WateringHistoryView> {
  final api = GreenhouseApi();
  List<PumpHistoryEntry>? history;
  bool failed = false;
  bool newestFirst = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final entries = await api.loadPumpHistory();
      if (mounted) setState(() => history = entries);
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
    final entries = history == null
        ? null
        : (List<PumpHistoryEntry>.from(history!)..sort(
            (a, b) => newestFirst
                ? (b.recordedAt ?? DateTime(0)).compareTo(
                    a.recordedAt ?? DateTime(0),
                  )
                : (a.recordedAt ?? DateTime(0)).compareTo(
                    b.recordedAt ?? DateTime(0),
                  ),
          ));

    return Scaffold(
      body: Row(
        children: [
          const SideBar(),
          Expanded(
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Panel(
                  title: 'Water Usage History',
                  actions: [
                    SortMenu(
                      onChanged: (value) => setState(() => newestFirst = value),
                    ),
                  ],
                  fillHeight: true,
                  child: failed
                      ? const Center(
                          child: Text(
                            'Could not load watering history',
                            style: TextStyle(color: Colors.black54),
                          ),
                        )
                      : entries == null
                      ? const Center(child: CircularProgressIndicator())
                      : entries.isEmpty
                      ? const EmptyHistory()
                      : ListView(
                          children: [
                            for (final entry in entries)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(
                                  Icons.water_drop_outlined,
                                  color: Color(0xff2d7600),
                                ),
                                title: Text(pumpLabel(entry)),
                                subtitle: Text(
                                  formatRecordedAt(entry.recordedAt),
                                ),
                                trailing: Text(formatLiters(entry.liters)),
                              ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
