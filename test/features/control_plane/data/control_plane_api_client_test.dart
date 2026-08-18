import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pterodactyl_mobile/core/error/app_exception.dart';
import 'package:pterodactyl_mobile/features/control_plane/data/control_plane_api_client.dart';

import '../../../support/fake_http_client_adapter.dart';

/// [ControlPlaneApiClient] is a slimmed-down sibling of
/// `PterodactylApiClient` (same `_request`/`ApiExceptionMapper` machinery,
/// already exhaustively tested for every status code in
/// `pterodactyl_api_client_test.dart`) — this only needs to prove the
/// get/post wiring itself is correct, not re-derive every mapping case.
ControlPlaneApiClient _client(FutureOr<ResponseBody> Function(RequestOptions) handler) {
  final dio = Dio(BaseOptions(baseUrl: 'https://cp.example.com'))..httpClientAdapter = FakeHttpClientAdapter(handler);
  return ControlPlaneApiClient(dio: dio);
}

void main() {
  test('get() sends a GET request and parses a successful JSON body', () async {
    RequestOptions? captured;
    final client = _client((options) {
      captured = options;
      return jsonResponseBody({'value': 7});
    });

    final result = await client.get<int>('/servers', parser: (data) => (data as Map<String, dynamic>)['value'] as int);

    expect(result.fold(onSuccess: (v) => v, onFailure: (_) => -1), 7);
    expect(captured!.method, 'GET');
    expect(captured!.path, '/servers');
  });

  test('post() sends the given body as JSON', () async {
    RequestOptions? captured;
    final client = _client((options) {
      captured = options;
      return jsonResponseBody({'accepted': true});
    });

    await client.post<void>('/servers/x/power', data: {'action': 'start'}, parser: (_) {});

    expect(captured!.method, 'POST');
    expect(captured!.data, {'action': 'start'});
  });

  test('a 401 response maps to UnauthorizedException', () async {
    final client = _client((_) => jsonResponseBody({}, statusCode: 401));

    final result = await client.get<void>('/servers', parser: (_) {});

    expect(result.fold(onSuccess: (_) => null, onFailure: (e) => e), isA<UnauthorizedException>());
  });

  test('a body the parser rejects maps to InvalidResponseException, not a crash', () async {
    final client = _client((_) => jsonResponseBody({'unexpected': 'shape'}));

    final result = await client.get<int>('/servers', parser: (_) => throw const FormatException('nope'));

    expect(result.fold(onSuccess: (_) => null, onFailure: (e) => e), isA<InvalidResponseException>());
  });
}
