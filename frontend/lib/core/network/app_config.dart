import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// The API origin used when neither the build nor `config.json` sets one.
const _defaultApiBaseUrl = 'http://localhost:8000';

/// The `API_BASE_URL` compile-time define, empty when the build did not set it.
const _definedApiBaseUrl = String.fromEnvironment('API_BASE_URL');

String _apiBaseUrl = _normalize(
  _definedApiBaseUrl.isEmpty ? _defaultApiBaseUrl : _definedApiBaseUrl,
);

/// The base URL of the API, with any trailing slash stripped.
///
/// Precedence: the `API_BASE_URL` compile-time define, then `config.json`
/// served next to the app, then [_defaultApiBaseUrl].
String get apiBaseUrl => _apiBaseUrl;

/// Loads `config.json` from the origin the app is served from.
///
/// A deployed web build can be pointed at another API by replacing
/// `config.json` next to `index.html`, without rebuilding. A build made with
/// `--dart-define=API_BASE_URL=...` already carries its origin, so the file is
/// only consulted when the define is absent. A missing or malformed file
/// leaves the current value untouched.
Future<void> loadAppConfig({http.Client? client, Uri? configUri}) async {
  if (!kIsWeb && configUri == null) return;
  if (_definedApiBaseUrl.isNotEmpty) return;

  final uri = configUri ?? Uri.base.resolve('config.json');
  final configClient = client ?? http.Client();
  try {
    final response = await configClient
        .get(uri, headers: const {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 3));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      debugPrint(
        'config.json returned ${response.statusCode}; keeping $apiBaseUrl',
      );
      return;
    }
    final json = jsonDecode(response.body);
    if (json is! Map<String, dynamic>) {
      debugPrint('config.json is not a JSON object; keeping $apiBaseUrl');
      return;
    }
    final value = json['API_BASE_URL'];
    if (value is! String || value.trim().isEmpty) {
      debugPrint('config.json has no API_BASE_URL; keeping $apiBaseUrl');
      return;
    }
    _apiBaseUrl = _normalize(value);
  } on Object catch (error) {
    debugPrint('config.json could not be read ($error); keeping $apiBaseUrl');
  } finally {
    if (client == null) configClient.close();
  }
}

/// Restores the build-time value, so tests do not leak configuration.
@visibleForTesting
void resetAppConfig() {
  _apiBaseUrl = _normalize(
    _definedApiBaseUrl.isEmpty ? _defaultApiBaseUrl : _definedApiBaseUrl,
  );
}

String _normalize(String value) {
  final trimmed = value.trim();
  return trimmed.endsWith('/')
      ? trimmed.substring(0, trimmed.length - 1)
      : trimmed;
}
