import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pterodactyl_mobile/core/error/app_exception.dart';
import 'package:pterodactyl_mobile/core/network/pterodactyl_api_client.dart';
import 'package:pterodactyl_mobile/features/console/data/console_api.dart';

import '../../../support/fake_http_client_adapter.dart';

ConsoleApi _buildApi(FakeHttpClientAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://panel.example.com'))..httpClientAdapter = adapter;
  return ConsoleApi(PterodactylApiClient(dio: dio));
}

void main() {
  group('ConsoleApi.getWebsocketToken', () {
    test('sends GET to /api/client/servers/{server}/websocket', () async {
      final adapter = FakeHttpClientAdapter(
        (options) async => jsonResponseBody({
          'data': {'token': 'jwt-value', 'socket': 'wss://node.example.com/api/servers/uuid/ws'},
        }),
      );
      final api = _buildApi(adapter);

      await api.getWebsocketToken('d3aac109');

      expect(adapter.lastRequest?.method, 'GET');
      expect(adapter.lastRequest?.path, '/api/client/servers/d3aac109/websocket');
    });

    test('parses the bespoke {"data": {...}} shape (not the Fractal envelope)', () async {
      final adapter = FakeHttpClientAdapter(
        (options) async => jsonResponseBody({
          'data': {'token': 'jwt-value', 'socket': 'wss://node.example.com/api/servers/uuid/ws'},
        }),
      );
      final api = _buildApi(adapter);

      final result = await api.getWebsocketToken('d3aac109');

      final dto = result.fold(onSuccess: (value) => value, onFailure: (error) => throw error);
      expect(dto.token, 'jwt-value');
      expect(dto.socketUrl, 'wss://node.example.com/api/servers/uuid/ws');
    });

    test('maps a response missing the expected shape to InvalidResponseException instead of crashing', () async {
      final adapter = FakeHttpClientAdapter(
        (options) async => jsonResponseBody({'object': 'server', 'attributes': {}}),
      );
      final api = _buildApi(adapter);

      final result = await api.getWebsocketToken('d3aac109');

      result.fold(
        onSuccess: (_) => fail('expected a failure'),
        onFailure: (error) => expect(error, isA<InvalidResponseException>()),
      );
    });

    test('maps an HTTP 401 response to UnauthorizedException', () async {
      final adapter = FakeHttpClientAdapter((options) async => jsonResponseBody({'errors': []}, statusCode: 401));
      final api = _buildApi(adapter);

      final result = await api.getWebsocketToken('d3aac109');

      result.fold(
        onSuccess: (_) => fail('expected a failure'),
        onFailure: (error) => expect(error, isA<UnauthorizedException>()),
      );
    });

    test('maps a connection error to NetworkException', () async {
      final adapter = FakeHttpClientAdapter(
        (options) async => throw DioException(requestOptions: options, type: DioExceptionType.connectionError),
      );
      final api = _buildApi(adapter);

      final result = await api.getWebsocketToken('d3aac109');

      result.fold(
        onSuccess: (_) => fail('expected a failure'),
        onFailure: (error) => expect(error, isA<NetworkException>()),
      );
    });
  });
}
