import 'package:flutter/material.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/network/sensor_ws.dart';
import 'package:frontend/core/widgets/conditions_card.dart';
import 'package:frontend/core/widgets/side_bar.dart';
import 'package:frontend/features/home/presentation/viewmodel/home_view_model.dart';
import 'package:frontend/features/home/presentation/widgets/alerts_card.dart';
import 'package:frontend/features/home/presentation/widgets/history_summary.dart';
import 'package:frontend/features/home/presentation/widgets/pump_card.dart';
import 'package:frontend/features/home/presentation/widgets/usage_chart.dart';

/// The dashboard.
///
/// It owns its `HomeViewModel`, which is created in `initState` and disposed
/// with the view.
class HomeView extends StatefulWidget {
  const HomeView({super.key, this.api, this.feed});

  final GreenhouseApi? api;
  final SensorFeed? feed;

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  late final HomeViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = HomeViewModel(api: widget.api, feed: widget.feed)..start();
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
      builder: (context, _) => Scaffold(
        body: Row(
          children: [
            const SideBar(),
            Expanded(
              child: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ConditionsCard(
                        snapshot: _viewModel.snapshot,
                        todayUsageLiters: _viewModel.todayUsageLiters,
                        failed: _viewModel.snapshotFailed,
                      ),
                      const SizedBox(height: 22),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final wide = constraints.maxWidth > 1050;
                          return wide
                              ? Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: UsageChart(
                                        buckets: _viewModel.usageBuckets,
                                        maxLiters: _viewModel.usageMaxLiters,
                                        range: _viewModel.usageRange,
                                        onRangeChanged: _viewModel.setUsageRange,
                                        failed: _viewModel.historyFailed,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    SizedBox(
                                      width: 300,
                                      child: HistorySummary(
                                        history: _viewModel.history,
                                        failed: _viewModel.historyFailed,
                                      ),
                                    ),
                                  ],
                                )
                              : Column(
                                  children: [
                                    UsageChart(
                                      buckets: _viewModel.usageBuckets,
                                      maxLiters: _viewModel.usageMaxLiters,
                                      range: _viewModel.usageRange,
                                      onRangeChanged: _viewModel.setUsageRange,
                                      failed: _viewModel.historyFailed,
                                    ),
                                    const SizedBox(height: 16),
                                    HistorySummary(
                                      history: _viewModel.history,
                                      failed: _viewModel.historyFailed,
                                    ),
                                  ],
                                );
                        },
                      ),
                      const SizedBox(height: 22),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final columns = constraints.maxWidth > 850
                              ? 3
                              : constraints.maxWidth > 500
                              ? 2
                              : 1;
                          return Container(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                            decoration: BoxDecoration(
                              color: const Color(0xffccdec3),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Sensor Status',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                GridView.count(
                                  crossAxisCount: columns,
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  crossAxisSpacing: 14,
                                  mainAxisSpacing: 14,
                                  childAspectRatio: 1.1,
                                  children: [
                                    for (final pump in _viewModel.pumps)
                                      PumpCard(
                                        key: ValueKey(pump.id),
                                        name: 'Water Pump #${pump.id}',
                                        pumpId: pump.id,
                                        initialMode: pump.mode,
                                        onModeChanged:
                                            _viewModel.updatePumpMode,
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 22),
                      AlertsCard(
                        alerts: _viewModel.alerts,
                        failed: _viewModel.alertsFailed,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
