import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/features/sensors/data/sensor_reading.dart';

/// Turns a websocket message into a reading. Returns null when the message is
/// not a sensor reading.
SensorReading? sensorReadingFromMessage(dynamic event) {
  try {
    final json = jsonDecode(event as String) as Map<String, dynamic>;
    if (!json.containsKey('moisture_level')) return null;
    return SensorReading.fromJson(json);
  } catch (_) {
    return null;
  }
}

/// The live sensor feed.
///
/// It subscribes to the same `/mc-ws/` endpoint the microcontroller publishes
/// to, derives the websocket URL from the api base url by rewriting `http` to
/// `ws`, and reconnects every 5 seconds.
class SensorFeed {
  SensorFeed({String? baseUrl}) : _baseUrl = baseUrl ?? apiBaseUrl;

  final String _baseUrl;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  bool _disposed = false;
  final _controller = StreamController<SensorReading>.broadcast();

  /// The readings as a broadcast stream, several listeners can share it.
  Stream<SensorReading> get readings => _controller.stream;

  void connect() {
    if (_disposed || _channel != null) return;
    final wsBase = _baseUrl.replaceFirst(RegExp(r'^http'), 'ws');
    try {
      final channel = WebSocketChannel.connect(Uri.parse('$wsBase/mc-ws/'));
      _channel = channel;
      _subscription = channel.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
      );
    } catch (_) {
      _closeChannel();
      _scheduleReconnect();
    }
  }

  /// Pushes a reading into the feed, used by the tests.
  @visibleForTesting
  void publish(SensorReading reading) {
    if (_disposed) return;
    _controller.add(reading);
  }

  void _onMessage(dynamic event) {
    final reading = sensorReadingFromMessage(event);
    if (reading == null) return;
    _controller.add(reading);
  }

  void _onError(Object error) {
    _closeChannel();
    _scheduleReconnect();
  }

  void _onDone() {
    _closeChannel();
    _scheduleReconnect();
  }

  /// Retries the connection in 5 seconds, only one retry is pending at a time.
  void _scheduleReconnect() {
    if (_disposed || _reconnectTimer != null) return;
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      _reconnectTimer = null;
      connect();
    });
  }

  void _closeChannel() {
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
  }

  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _closeChannel();
    _controller.close();
  }
}
