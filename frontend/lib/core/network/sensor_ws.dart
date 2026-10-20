import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/features/sensors/data/sensor_reading.dart';

class SensorFeed {
  SensorFeed({String? baseUrl}) : _baseUrl = baseUrl ?? apiBaseUrl;

  final String _baseUrl;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  final _controller = StreamController<SensorReading>.broadcast();

  Stream<SensorReading> get readings => _controller.stream;

  void connect() {
    final wsBase = _baseUrl.replaceFirst(RegExp(r'^http'), 'ws');
    _channel = WebSocketChannel.connect(Uri.parse('$wsBase/mc-ws/'));
    _subscription = _channel!.stream.listen(_onMessage);
  }

  void _onMessage(dynamic event) {
    try {
      final json = jsonDecode(event as String) as Map<String, dynamic>;
      if (!json.containsKey('moisture_level')) return;
      _controller.add(SensorReading.fromJson(json));
    } catch (_) {}
  }

  void dispose() {
    _subscription?.cancel();
    _channel?.sink.close();
    _controller.close();
  }
}
