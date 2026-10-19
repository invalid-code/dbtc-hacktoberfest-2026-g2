import 'package:flutter/material.dart';
import 'dart:async';

import 'api_client.dart';

void main() => runApp(const GreenhouseApp());

class GreenhouseApp extends StatelessWidget {
  const GreenhouseApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Greenhouse Control',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff2d7600)),
      scaffoldBackgroundColor: const Color(0xfff0fae7),
      fontFamily: 'Roboto',
      useMaterial3: true,
    ),
    onGenerateRoute: (settings) {
      Widget page;

      switch (settings.name) {
        case '/':
          page = const HomePage();
          break;
        case '/watering-history':
          page = const WateringHistoryPage();
          break;
        case '/sensor-reading':
          page = const SensorReadingsPage();
          break;
        default:
          page = const HomePage();
      }
      return PageRouteBuilder(
        settings: settings,
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      );
    },
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePage();
}

class _HomePage extends State<HomePage> {
  final api = GreenhouseApi();
  GreenhouseSnapshot? snapshot;
  Timer? _refreshTimer;

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
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      api.loadSnapshot().then((value) {
        if (mounted) setState(() => snapshot = value);
      }).catchError((_) {});
    });
  }

  @override
  void dispose() {
    api.dispose();
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          SideBar(),
          Expanded(
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16), // TODO for now arbritrary value
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                  _ConditionsCard(snapshot: snapshot),
                  const SizedBox(height: 22),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth > 1050;
                      return wide
                          ? const Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: _UsageChart()),
                                SizedBox(width: 16),
                                SizedBox(width: 300, child: _HistorySummary()),
                              ],
                            )
                          : const Column(
                              children: [
                                _UsageChart(),
                                SizedBox(height: 16),
                                _HistorySummary(),
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
                                _PumpCard(
                                  name: 'Water Pump #1',
                                  pumpId: _pumpId(0),
                                ),
                                _PumpCard(
                                  name: 'Water Pump #2',
                                  pumpId: _pumpId(1),
                                ),
                                _PumpCard(
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
                  const _AlertsCard(),
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

class WateringHistoryPage extends StatefulWidget {
  const WateringHistoryPage({super.key});

  @override
  State<WateringHistoryPage> createState() => _WateringHistoryPage();
}

class _WateringHistoryPage extends State<WateringHistoryPage> {
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
                child: _Panel(
                  title: 'Water Usage History',
                  actions: [
                    _SortMenu(
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
                      ? const _EmptyHistory()
                      : ListView(
                          children: [
                            for (final entry in entries)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(
                                  Icons.water_drop_outlined,
                                  color: Color(0xff2d7600),
                                ),
                                title: Text(_pumpLabel(entry)),
                                subtitle: Text(
                                  _formatRecordedAt(entry.recordedAt),
                                ),
                                trailing: Text(_formatLiters(entry.liters)),
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

class _SortMenu extends StatelessWidget {
  const _SortMenu({required this.onChanged});

  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<bool>(
      tooltip: 'Sort by timestamp',
      onSelected: onChanged,
      itemBuilder: (_) => const [
        PopupMenuItem(value: true, child: Text('Newest first')),
        PopupMenuItem(value: false, child: Text('Oldest first')),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xffd6d6d6)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Timestamp',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const Icon(Icons.arrow_drop_down, size: 20),
          ],
        ),
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: const [
        Icon(Icons.layers_clear_outlined, size: 34, color: Colors.black54),
        SizedBox(height: 8),
        Text('History Clear!', style: TextStyle(color: Colors.black54)),
      ],
    ),
  );
}

class SensorReadingsPage extends StatefulWidget {
  const SensorReadingsPage({super.key});

  @override
  State<SensorReadingsPage> createState() => _SensorReadingPage();
}

class _SensorReadingPage extends State<SensorReadingsPage> {
  final api = GreenhouseApi();
  List<SensorReading>? readings;
  bool failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final entries = await api.loadSensorReadings();
      if (mounted) setState(() => readings = entries);
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
    final entries = readings;
    final loading = entries == null && !failed;
    final hasData = entries != null && entries.isNotEmpty;
    final values = hasData
        ? entries
              .map((e) => (e.moisture / 100).clamp(0.0, 1.0).toDouble())
              .toList()
        : const <double>[];

    return Scaffold(
      body: Row(
        children: [
          const SideBar(),
          Expanded(
            child: SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(16), // for now arbritrary value
                children: [
                  _ConditionsCard(
                    snapshot: hasData
                        ? GreenhouseSnapshot(
                            sensor: entries.last,
                            pumps: const [],
                          )
                        : null,
                  ),
                  const SizedBox(height: 22),
                  _Panel(
                    title: 'Temperature Trends',
                    child: SizedBox(
                      height: 280,
                      child: CustomPaint(
                        painter: _ChartPainter(),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _Panel(
                    title: 'Moisture Trends',
                    child: failed
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
                              painter: _LineChartPainter(values: values),
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
  }
}

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
          onTap: () {
            Navigator.pushNamed(context, '/');
          },
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
          onTap: () {
            Navigator.pushNamed(context, '/watering-history');
          },
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
            child: Row(
              children: [
                Icon(Icons.eco_outlined),
                SizedBox(width: 12),
                const Flexible(
                  child: Text("Watering History", overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        InkWell(
          onTap: () {
            Navigator.pushNamed(context, '/sensor-reading');
          },
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
            child: Row(
              children: [
                Icon(Icons.bar_chart_rounded),
                SizedBox(width: 12),
                const Flexible(
                  child: Text("Sensor Readings", overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _ConditionsCard extends StatefulWidget {
  const _ConditionsCard({this.snapshot});

  final GreenhouseSnapshot? snapshot;

  @override
  State<_ConditionsCard> createState() => _ConditionsCardState();
}

class _ConditionsCardState extends State<_ConditionsCard> {
  final api = GreenhouseApi();
  double? todayUsageLiters;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final liters = await api.loadTodayWaterUsage();
      if (mounted) setState(() => todayUsageLiters = liters);
    } catch (_) {}
  }

  @override
  void dispose() {
    api.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    final usage = todayUsageLiters;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xffccdec3),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Current Conditions',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              const Icon(Icons.info_outline, size: 20, color: Colors.black54),
              const SizedBox(width: 8),
              const Flexible(
                child: Text(
                  'Sensor readings represent greenhouse metrics',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.black54),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) => GridView.count(
              crossAxisCount: constraints.maxWidth > 700
                  ? 4
                  : constraints.maxWidth > 420
                  ? 2
                  : 1,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              childAspectRatio: 1.5,
              children: [
                _MetricCard(
                  label: "Today's water usage",
                  value: usage == null ? '—' : _formatLiters(usage),
                ),
                _MetricCard(
                  label: 'Soil Moisture',
                  value: '${snapshot?.sensor?.moisture ?? 45}%',
                ),
                _MetricCard(
                  label: 'Humidity',
                  value: '${snapshot?.sensor?.waterLevel ?? 45}%',
                ),
                const _MetricCard(label: 'Temperature', value: '31 C'),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              'Last updated · ${_formatRecordedAt(snapshot?.sensor?.recordedAt)}',
              style: const TextStyle(color: Colors.black54, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15),
        ),
        const SizedBox(height: 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}

class _UsageChart extends StatefulWidget {
  const _UsageChart();

  @override
  State<_UsageChart> createState() => _UsageChartState();
}

class _UsageChartState extends State<_UsageChart> {
  final api = GreenhouseApi();
  List<double>? monthlyUsage;
  bool failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final entries = await api.loadPumpHistory();
      if (mounted) {
        setState(
          () => monthlyUsage = entries.isEmpty
              ? const []
              : _monthlyUsage(entries),
        );
      }
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  List<double> _monthlyUsage(List<PumpHistoryEntry> entries) {
    final year = DateTime.now().year;
    final totals = List<double>.filled(12, 0);
    for (final entry in entries) {
      final at = entry.recordedAt;
      if (at == null || at.year != year) continue;
      totals[at.month - 1] += entry.liters;
    }
    final max = totals.reduce((a, b) => a > b ? a : b);
    if (max <= 0) return totals;
    return totals.map((value) => value / max).toList();
  }

  @override
  void dispose() {
    api.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final usage = monthlyUsage;
    return _Panel(
      title: 'Water Usage History',
      child: SizedBox(
        height: 340,
        child: failed
            ? const Center(
                child: Text(
                  'Could not load water usage',
                  style: TextStyle(color: Colors.black54),
                ),
              )
            : usage == null
            ? const Center(child: CircularProgressIndicator())
            : usage.isEmpty
            ? const Center(
                child: Text(
                  'No water usage recorded yet',
                  style: TextStyle(color: Colors.black54),
                ),
              )
            : CustomPaint(
                painter: _ChartPainter(values: usage),
                child: const SizedBox.expand(),
              ),
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  const _ChartPainter({this.values});

  final List<double>? values;

  static const fallbackValues = [
    0.72,
    0.51,
    0.62,
    0.43,
    0.8,
    0.55,
    0.69,
    0.48,
    0.58,
    0.4,
    0.63,
    0.52,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    const left = 38.0;
    const top = 18.0;
    final chart = Rect.fromLTWH(
      left,
      top,
      size.width - left - 12,
      size.height - 48,
    );
    final grid = Paint()
      ..color = const Color(0xffb8b8b8)
      ..strokeWidth = 1;
    for (var i = 0; i < 8; i++) {
      final y = chart.top + chart.height * i / 7;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), grid);
    }
    for (var i = 0; i < 12; i++) {
      final x = chart.left + chart.width * i / 11;
      canvas.drawLine(
        Offset(x, chart.top),
        Offset(x, chart.bottom),
        grid..color = const Color(0xffe0e0e0),
      );
    }
    final line = Paint()
      ..color = const Color(0xff007300)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    final data = values ?? fallbackValues;
    final path = Path();
    for (var i = 0; i < data.length; i++) {
      final point = Offset(
        chart.left + chart.width * i / (data.length - 1),
        chart.bottom - chart.height * data[i],
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(path, line);
    final text = TextPainter(textDirection: TextDirection.ltr);
    const months = [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC',
    ];
    for (var i = 0; i < months.length; i++) {
      text.text = TextSpan(
        text: months[i],
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: Color(0xff424242),
        ),
      );
      text.layout();
      text.paint(
        canvas,
        Offset(
          chart.left + chart.width * i / 11 - text.width / 2,
          chart.bottom + 12,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter oldDelegate) =>
      oldDelegate.values != values;
}

class _LineChartPainter extends CustomPainter {
  const _LineChartPainter({required this.values});

  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) {
      final text = TextPainter(
        text: const TextSpan(
          text: 'Not enough data',
          style: TextStyle(fontSize: 13, color: Colors.black54),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(
        canvas,
        Offset((size.width - text.width) / 2, (size.height - text.height) / 2),
      );
      return;
    }

    const left = 38.0;
    const top = 18.0;
    final chart = Rect.fromLTWH(
      left,
      top,
      size.width - left - 12,
      size.height - 48,
    );
    final grid = Paint()
      ..color = const Color(0xffb8b8b8)
      ..strokeWidth = 1;
    for (var i = 0; i < 8; i++) {
      final y = chart.top + chart.height * i / 7;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), grid);
    }

    final line = Paint()
      ..color = const Color(0xff007300)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final point = Offset(
        chart.left + chart.width * i / (values.length - 1),
        chart.bottom - chart.height * values[i],
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(path, line);

    final text = TextPainter(textDirection: TextDirection.ltr);
    for (var i = 0; i < values.length; i++) {
      text.text = TextSpan(
        text: '${(values[i] * 100).round()}',
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: Color(0xff424242),
        ),
      );
      text.layout();
      text.paint(
        canvas,
        Offset(
          chart.left + chart.width * i / (values.length - 1) - text.width / 2,
          chart.bottom - chart.height * values[i] - text.height - 6,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) =>
      oldDelegate.values != values;
}

class _HistorySummary extends StatefulWidget {
  const _HistorySummary();

  @override
  State<_HistorySummary> createState() => _HistorySummaryState();
}

class _HistorySummaryState extends State<_HistorySummary> {
  final api = GreenhouseApi();
  List<PumpHistoryEntry>? history;
  bool failed = false;

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
    final entries = history;
    return _Panel(
      title: 'History Summary',
      child: failed
          ? const Text(
              'Could not load history',
              style: TextStyle(color: Colors.black54),
            )
          : entries == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: CircularProgressIndicator(),
              ),
            )
          : _summary(entries),
    );
  }

  Widget _summary(List<PumpHistoryEntry> entries) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    bool sameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;

    bool onDay(PumpHistoryEntry entry, DateTime day) =>
        entry.recordedAt != null && sameDay(entry.recordedAt!, day);

    final todayEntries = entries.where((e) => onDay(e, today)).toList();
    final yesterdayEntries = entries.where((e) => onDay(e, yesterday)).toList();

    if (entries.isEmpty) {
      return const SizedBox(
        height: 340,
        child: Center(
          child: Text(
            'No water usage recorded yet',
            style: TextStyle(color: Colors.black54),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Today',
          style: TextStyle(fontSize: 17, color: Colors.black54),
        ),
        const SizedBox(height: 12),
        if (todayEntries.isEmpty)
          const Text('No water usage', style: TextStyle(color: Colors.black54))
        else
          ...todayEntries.map(_summaryLine),
        const SizedBox(height: 22),
        const Divider(),
        const SizedBox(height: 12),
        const Text(
          'Yesterday',
          style: TextStyle(fontSize: 17, color: Colors.black54),
        ),
        const SizedBox(height: 12),
        if (yesterdayEntries.isEmpty)
          const Text('No water usage', style: TextStyle(color: Colors.black54))
        else
          ...yesterdayEntries.map(_summaryLine),
      ],
    );
  }

  Widget _summaryLine(PumpHistoryEntry entry) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      '${_pumpLabel(entry)}: ${_formatLiters(entry.liters)} at '
      '${_formatTime(entry.recordedAt)}',
    ),
  );
}

class _PumpCard extends StatefulWidget {
  const _PumpCard({required this.name, required this.pumpId});
  final String name;
  final int pumpId;

  @override
  State<_PumpCard> createState() => _PumpCardState();
}

class _PumpCardState extends State<_PumpCard> {
  bool running = true;
  String mode = 'Drip';
  final api = GreenhouseApi();

  @override
  void dispose() {
    api.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.name,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Text(
          running ? 'Running' : 'Stopped',
          style: const TextStyle(fontSize: 16),
        ),
        const SizedBox(height: 6),
        DropdownButton<String>(
          value: mode,
          isDense: true,
          isExpanded: true,
          items: ['Fast', 'Slow', 'Drip', 'Sprinkle']
              .map(
                (value) =>
                    DropdownMenuItem(value: value, child: Text('Mode: $value')),
              )
              .toList(),
          onChanged: (value) async {
            final next = value ?? mode;
            setState(() => mode = next);
            try {
              await api.updatePumpMode(widget.pumpId, _modeValue(next));
            } catch (_) {}
          },
        ),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: running
                  ? const Color(0xff760202)
                  : const Color(0xff384b2c),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(5),
              ),
            ),
            onPressed: () => setState(() => running = !running),
            child: Text(running ? 'Stop' : 'Start'),
          ),
        ),
      ],
    ),
  );

  int _modeValue(String value) =>
      ['Fast', 'Slow', 'Drip', 'Sprinkle'].indexOf(value);
}

class _AlertsCard extends StatefulWidget {
  const _AlertsCard();

  @override
  State<_AlertsCard> createState() => _AlertsCardState();
}

class _AlertsCardState extends State<_AlertsCard> {
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
    return _Panel(
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

class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.child,
    this.fillHeight = false,
    this.actions,
  });
  final String title;
  final Widget child;
  final bool fillHeight;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xffccdec3),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              ...?actions,
            ],
          ),
          const SizedBox(height: 14),
          if (fillHeight) Expanded(child: content) else content,
        ],
      ),
    );
  }
}

String _pumpLabel(PumpHistoryEntry entry) =>
    entry.pump == null ? 'Pump' : 'Pump #${entry.pump}';

String _formatLiters(double liters) {
  final num value = liters == liters.roundToDouble() ? liters.toInt() : liters;
  return '$value L';
}

String _formatTime(DateTime? recordedAt) {
  if (recordedAt == null) return 'Unknown time';
  final hour24 = recordedAt.hour;
  final hour = hour24 % 12 == 0 ? 12 : hour24 % 12;
  final minute = recordedAt.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${hour24 < 12 ? 'AM' : 'PM'}';
}

String _formatRecordedAt(DateTime? recordedAt) {
  if (recordedAt == null) return 'Unknown date';
  const months = [
    'Jan.',
    'Feb.',
    'Mar.',
    'Apr.',
    'May',
    'Jun.',
    'Jul.',
    'Aug.',
    'Sep.',
    'Oct.',
    'Nov.',
    'Dec.',
  ];
  return '${months[recordedAt.month - 1]} ${recordedAt.day}, '
      '${recordedAt.year} · ${_formatTime(recordedAt)}';
}
