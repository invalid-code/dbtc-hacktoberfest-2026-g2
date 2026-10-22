import 'package:flutter/material.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/network/sensor_ws.dart';
import 'package:frontend/core/widgets/chart_painter.dart';
import 'package:frontend/core/widgets/conditions_card.dart';
import 'package:frontend/core/widgets/panel.dart';
import 'package:frontend/core/widgets/side_bar.dart';
import 'package:frontend/core/widgets/time_range_filter.dart';
import 'package:frontend/features/sensors/presentation/viewmodel/sensor_readings_view_model.dart';
import 'package:frontend/features/sensors/presentation/widgets/line_chart_painter.dart';

const _trendHeight = 280.0;

/// The current conditions plus the temperature and the moisture trend panels.
class SensorReadingsView extends StatefulWidget {
  const SensorReadingsView({super.key, this.api, this.feed});

  final GreenhouseApi? api;
  final SensorFeed? feed;

  @override
  State<SensorReadingsView> createState() => _SensorReadingsViewState();
}

class _SensorReadingsViewState extends State<SensorReadingsView> {
  late final SensorReadingsViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = SensorReadingsViewModel(api: widget.api, feed: widget.feed)
      ..start();
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
        final entries = _viewModel.readings;
        final loading = entries == null && !_viewModel.failed;
        final hasData = entries != null && entries.isNotEmpty;

        return Scaffold(
          body: Row(
            children: [
              const SideBar(),
              Expanded(
                child: SafeArea(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      ConditionsCard(
                        snapshot: hasData
                            ? GreenhouseSnapshot(
                                sensor: entries.last,
                                pumps: const [],
                              )
                            : null,
                      ),
                      const SizedBox(height: 22),
                      Panel(
                        title: 'Temperature Trends',
                        actions: [
                          TimeRangeFilter(
                            value: _viewModel.temperatureRange,
                            onChanged: _viewModel.setTemperatureRange,
                          ),
                        ],
                        child: SizedBox(
                          height: _trendHeight,
                          child: _viewModel.failed
                              ? const Center(
                                  child: Text(
                                    'Could not load sensor readings',
                                    style: TextStyle(color: Colors.black54),
                                  ),
                                )
                              : loading
                              ? const Center(
                                  child: CircularProgressIndicator(),
                                )
                              : !hasData
                              ? const Center(
                                  child: Text(
                                    'No sensor readings yet',
                                    style: TextStyle(color: Colors.black54),
                                  ),
                                )
                              : CustomPaint(
                                  painter: ChartPainter(
                                    buckets: _viewModel.temperatureBuckets,
                                    maxValue: 50,
                                  ),
                                  child: const SizedBox.expand(),
                                ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Panel(
                        title: 'Moisture Trends',
                        actions: [
                          TimeRangeFilter(
                            value: _viewModel.moistureRange,
                            onChanged: _viewModel.setMoistureRange,
                          ),
                        ],
                        child: SizedBox(
                          height: _trendHeight,
                          child: _viewModel.failed
                              ? const Center(
                                  child: Text(
                                    'Could not load sensor readings',
                                    style: TextStyle(color: Colors.black54),
                                  ),
                                )
                              : loading
                              ? const Center(
                                  child: CircularProgressIndicator(),
                                )
                              : !hasData
                              ? const Center(
                                  child: Text(
                                    'No sensor readings yet',
                                    style: TextStyle(color: Colors.black54),
                                  ),
                                )
                              : CustomPaint(
                                  painter: LineChartPainter(
                                    buckets: _viewModel.moistureBuckets,
                                    maxValue: 100,
                                    valueSuffix: '%',
                                  ),
                                  child: const SizedBox.expand(),
                                ),
                        ),
                      ),
                    ],
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
