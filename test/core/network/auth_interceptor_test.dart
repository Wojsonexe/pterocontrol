import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pterodactyl_mobile/core/network/interceptors/auth_interceptor.dart';

import '../../support/fake_http_client_adapter.dart';

Dio _buildDio(FakeHttpClientAdapter adapter, AuthTokenProvider tokenProvider) {
  return Dio(BaseOptions(baseUrl: 'https://panel.example.com'))
    ..httpClientAdapter = adapter
    ..interceptors.add(AuthInterceptor(tokenProvider));
}

void main() {
  group('AuthInterceptor', () {
    test('attaches Authorization: Bearer <token> when a token is available', () async {
      final adapter = FakeHttpClientAdapter((options) async => jsonResponseBody({'ok': true}));
      final dio = _buildDio(adapter, () async => 'test-token');

      await dio.get<dynamic>('/api/client');

      expect(adapter.lastRequest?.headers['Authorization'], 'Bearer test-token');
    });

    test('sends no Authorization header when the token provider resolves null', () async {
      final adapter = FakeHttpClientAdapter((options) async => jsonResponseBody({'ok': true}));
      final dio = _buildDio(adapter, () async => null);

      await dio.get<dynamic>('/api/client');

      expect(adapter.lastRequest?.headers.containsKey('Authorization'), isFalse);
    });

    test('sends no Authorization header when the token provider resolves an empty string', () async {
      final adapter = FakeHttpClientAdapter((options) async => jsonResponseBody({'ok': true}));
      final dio = _buildDio(adapter, () async => '');

      await dio.get<dynamic>('/api/client');

      expect(adapter.lastRequest?.headers.containsKey('Authorization'), isFalse);
    });
  });
}
