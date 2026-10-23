import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:frontend/core/network/app_config.dart';

const _configUri = 'https://app.example.com/config.json';

void main() {
  setUp(resetAppConfig);
  tearDown(resetAppConfig);

  test(
    'reads API_BASE_URL from config.json and strips a trailing slash',
    () async {
      final client = MockClient((request) async {
        expect(request.url, Uri.parse(_configUri));
        return http.Response(
          '{"API_BASE_URL":"https://api.example.com/"}',
          200,
        );
      });

      await loadAppConfig(client: client, configUri: Uri.parse(_configUri));

      expect(apiBaseUrl, 'https://api.example.com');
    },
  );

  test('trims whitespace around the configured origin', () async {
    final client = MockClient(
      (request) async =>
          http.Response('{"API_BASE_URL":"  https://api.example.com  "}', 200),
    );

    await loadAppConfig(client: client, configUri: Uri.parse(_configUri));

    expect(apiBaseUrl, 'https://api.example.com');
  });

  test('keeps the current origin when config.json is missing', () async {
    final before = apiBaseUrl;
    final client = MockClient((request) async => http.Response('nope', 404));

    await loadAppConfig(client: client, configUri: Uri.parse(_configUri));

    expect(apiBaseUrl, before);
  });

  test('keeps the current origin when config.json is malformed', () async {
    final before = apiBaseUrl;
    final client = MockClient((request) async => http.Response('{oops', 200));

    await loadAppConfig(client: client, configUri: Uri.parse(_configUri));

    expect(apiBaseUrl, before);
  });

  test('keeps the current origin when API_BASE_URL is empty', () async {
    final before = apiBaseUrl;
    final client = MockClient(
      (request) async => http.Response('{"API_BASE_URL":""}', 200),
    );

    await loadAppConfig(client: client, configUri: Uri.parse(_configUri));

    expect(apiBaseUrl, before);
  });
}
