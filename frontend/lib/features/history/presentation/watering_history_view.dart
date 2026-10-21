import 'package:flutter/material.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/widgets/empty_history.dart';
import 'package:frontend/core/widgets/formatting.dart';
import 'package:frontend/core/widgets/panel.dart';
import 'package:frontend/core/widgets/side_bar.dart';
import 'package:frontend/core/widgets/sort_menu.dart';
import 'package:frontend/features/history/presentation/viewmodel/watering_history_view_model.dart';

/// The full list of the waterings, with the sort toggle in the panel header.
class WateringHistoryView extends StatefulWidget {
  const WateringHistoryView({super.key, this.api});

  final GreenhouseApi? api;

  @override
  State<WateringHistoryView> createState() => _WateringHistoryViewState();
}

class _WateringHistoryViewState extends State<WateringHistoryView> {
  late final WateringHistoryViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = WateringHistoryViewModel(api: widget.api)..start();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        final entries = _viewModel.sortedHistory;
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
                          onChanged: _viewModel.setNewestFirst,
                        ),
                      ],
                      fillHeight: true,
                      child: _viewModel.failed
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
      },
    );
  }
}
