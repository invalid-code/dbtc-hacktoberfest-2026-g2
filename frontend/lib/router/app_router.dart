import 'package:go_router/go_router.dart';

import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/network/sensor_ws.dart';
import 'package:frontend/features/home/presentation/home_view.dart';
import 'package:frontend/features/history/presentation/watering_history_view.dart';
import 'package:frontend/features/sensors/presentation/sensor_readings_view.dart';
import 'package:frontend/router/routes.dart';

GoRouter buildRouter({
  GreenhouseApi Function()? api,
  SensorFeed Function()? feed,
}) => GoRouter(
  initialLocation: AppRoutes.home,
  routes: [
    GoRoute(
      path: AppRoutes.home,
      builder: (context, state) =>
          HomeView(api: api?.call(), feed: feed?.call()),
    ),
    GoRoute(
      path: AppRoutes.wateringHistory,
      builder: (context, state) => WateringHistoryView(api: api?.call()),
    ),
    GoRoute(
      path: AppRoutes.sensorReading,
      builder: (context, state) => SensorReadingsView(api: api?.call()),
    ),
  ],
);
