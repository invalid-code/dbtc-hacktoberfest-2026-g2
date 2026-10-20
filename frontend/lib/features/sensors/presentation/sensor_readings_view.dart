import 'package:flutter/material.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/widgets/chart_painter.dart';
import 'package:frontend/core/widgets/conditions_card.dart';
import 'package:frontend/core/widgets/panel.dart';
import 'package:frontend/core/widgets/side_bar.dart';
import 'package:frontend/features/sensors/data/sensor_reading.dart';
import 'package:frontend/features/sensors/presentation/viewmodel/sensor_readings_view_model.dart';
import 'package:frontend/features/sensors/presentation/widgets/line_chart_painter.dart';

class SensorReadingsView extends StatefulWidget {
  const SensorReadingsView({super.key});

  @override
  State<SensorReadingsView> createState() => _SensorReadingsViewState();
}

class _SensorReadingsViewState extends State<SensorReadingsView> {
  late final SensorReadingsViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = SensorReadingsViewModel()..start();
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
        final values = hasData
            ? entries
                  .map((e) => (e.moisture / 100).clamp(0.0, 1.0).toDouble())
                  .toList()
            : const <double>[];
        final tempValues = hasData
            ? entries
                  .map(
                    (e) => ((e.temperature ?? 0) / 50)
                        .clamp(0.0, 1.0)
                        .toDouble(),
                  )
                  .toList()
            : const <double>[];

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
                        child: _viewModel.failed
                            ? const Text(
                                'Could not load sensor readings',
                                style: TextStyle(color: Colors.black54),
                              )
                            : loading
                            ? const Center(
                                child: Padding(
                                  padding: EdgeInsets.symmetric(vertical: 24),
                                  child: CircularProgressIndicator(),
                                ),
                              )
                            : !hasData
                            ? const Text(
                                'No sensor readings yet',
                                style: TextStyle(color: Colors.black54),
                              )
                            : SizedBox(
                                height: 280,
                                child: CustomPaint(
                                  painter: ChartPainter(values: tempValues),
                                  child: const SizedBox.expand(),
                                ),
                              ),
                      ),
                      const SizedBox(height: 18),
                      Panel(
                        title: 'Moisture Trends',
                        child: _viewModel.failed
                            ? const Text(
                                'Could not load sensor readings',
                                style: TextStyle(color: Colors.black54),
                              )
                            : loading
                            ? const Center(
                                child: Padding(
                                  padding: EdgeInsets.symmetric(vertical: 24),
                                  child: CircularProgressIndicator(),
                                ),
                              )
                            : !hasData
                            ? const Text(
                                'No sensor readings yet',
                                style: TextStyle(color: Colors.black54),
                              )
                            : SizedBox(
                                height: 280,
                                child: CustomPaint(
                                  painter: LineChartPainter(values: values),
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
