import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'router/app_router.dart';

void main() => runApp(const GreenhouseApp());

class GreenhouseApp extends StatelessWidget {
  const GreenhouseApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    routerConfig: appRouter,
    debugShowCheckedModeBanner: false,
    title: 'Greenhouse Control',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff2d7600)),
      scaffoldBackgroundColor: const Color(0xfff0fae7),
      fontFamily: 'Roboto',
      useMaterial3: true,
    ),
  );
}
