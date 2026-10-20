import 'dart:async';

import 'package:flutter/material.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/network/sensor_ws.dart';
import 'package:frontend/core/widgets/conditions_card.dart';
import 'package:frontend/core/widgets/side_bar.dart';
import 'package:frontend/features/home/presentation/widgets/alerts_card.dart';
import 'package:frontend/features/home/presentation/widgets/history_summary.dart';
import 'package:frontend/features/home/presentation/widgets/pump_card.dart';
import 'package:frontend/features/home/presentation/widgets/usage_chart.dart';
import 'package:frontend/features/sensors/data/sensor_reading.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  final api = GreenhouseApi();
  final _feed = SensorFeed();
  GreenhouseSnapshot? snapshot;
  StreamSubscription<SensorReading>? _sensorSub;

  int _pumpId(int index) => snapshot != null && snapshot!.pumps.length > index
      ? snapshot!.pumps[index].id
      : index + 1;

  @override
  void initState() {
    super.initState();
    api
        .loadSnapshot()
        .then((value) {
          if (mounted) setState(() => snapshot = value);
        })
        .catchError((_) {});
    _sensorSub = _feed.readings.listen((reading) {
      if (!mounted) return;
      setState(() {
        snapshot = GreenhouseSnapshot(
          sensor: reading,
          pumps: snapshot?.pumps ?? const [],
        );
      });
    });
    _feed.connect();
  }

  @override
  void dispose() {
    _sensorSub?.cancel();
    _feed.dispose();
    api.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          const SideBar(),
          Expanded(
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(
                  16,
                ), // TODO for now arbritrary value
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ConditionsCard(snapshot: snapshot),
                    const SizedBox(height: 22),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final wide = constraints.maxWidth > 1050;
                        return wide
                            ? const Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: UsageChart()),
                                  SizedBox(width: 16),
                                  SizedBox(
                                    width: 300,
                                    child: HistorySummary(),
                                  ),
                                ],
                              )
                            : const Column(
                                children: [
                                  UsageChart(),
                                  SizedBox(height: 16),
                                  HistorySummary(),
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
                                  PumpCard(
                                    name: 'Water Pump #1',
                                    pumpId: _pumpId(0),
                                  ),
                                  PumpCard(
                                    name: 'Water Pump #2',
                                    pumpId: _pumpId(1),
                                  ),
                                  PumpCard(
                                    name: 'Water Pump #3',
                                    pumpId: _pumpId(2),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 22),
                    const AlertsCard(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
