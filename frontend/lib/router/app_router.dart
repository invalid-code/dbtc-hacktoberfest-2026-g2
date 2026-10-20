import 'package:go_router/go_router.dart';
import '../features/home/presentation/home_view.dart';
import '../features/history/presentation/watering_history_view.dart';
import '../features/sensors/presentation/sensor_readings_view.dart';
import 'routes.dart';

final appRouter = GoRouter(
  initialLocation: AppRoutes.home,
  routes: [
    GoRoute(
      path: AppRoutes.home,
      builder: (context, state) => const HomeView(),
    ),
    GoRoute(
      path: AppRoutes.wateringHistory,
      builder: (context, state) => const WateringHistoryView(),
    ),
    GoRoute(
      path: AppRoutes.sensorReading,
      builder: (context, state) => const SensorReadingsView(),
    ),
  ],
);