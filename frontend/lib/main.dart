import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/network/app_config.dart';
import 'package:frontend/core/network/sensor_ws.dart';
import 'package:frontend/router/app_router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadAppConfig();
  runApp(const GreenhouseApp());
}

/// The root of the app: it owns the router and the theme.
///
/// The `api` and `feed` factories are injection seams, the tests override them
/// to plug a fake API and a fake feed in.
class GreenhouseApp extends StatefulWidget {
  const GreenhouseApp({super.key, this.api, this.feed});

  /// Builds the API client used by the views. Overridden by tests.
  final GreenhouseApi Function()? api;

  /// Builds the live sensor feed used by the views. Overridden by tests.
  final SensorFeed Function()? feed;

  @override
  State<GreenhouseApp> createState() => _GreenhouseAppState();
}

class _GreenhouseAppState extends State<GreenhouseApp> {
  late final GoRouter _router = buildRouter(
    api: widget.api,
    feed: widget.feed,
  );

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    routerConfig: _router,
    debugShowCheckedModeBanner: false,
    title: 'Greenhouse Control',
    theme: ThemeData(
      // The deep green seed drives every accent colour of the app.
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff2d7600)),
      // The pale green backdrop the panels sit on.
      scaffoldBackgroundColor: const Color(0xfff0fae7),
      fontFamily: 'Roboto',
      useMaterial3: true,
    ),
  );
}
