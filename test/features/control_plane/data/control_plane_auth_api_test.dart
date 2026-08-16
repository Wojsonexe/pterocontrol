import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pterodactyl_mobile/core/error/app_exception.dart';
import 'package:pterodactyl_mobile/features/control_plane/data/control_plane_api_client.dart';
import 'package:pterodactyl_mobile/features/control_plane/data/control_plane_auth_api.dart';

import '../../../support/fake_http_client_adapter.dart';

/// Same fake-JWT construction as `jwt_payload_test.dart` — this is the
/// real shape `POST /auth/login` returns (see
/// `services/control-plane-api/src/auth/auth.controller.ts`), an
/// `accessToken` whose payload carries `tenantId`, not a separate field.
String _fakeJwt(Map<String, dynamic> payload) {
  final header = base64Url.encode(utf8.encode(jsonEncode({'alg': 'HS256'}))).replaceAll('=', '');
  final body = base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '');
  return '$header.$body.fake-signature';
}

void main() {
  test('login() parses accessToken, tenantId (from the JWT), and userEmail on success', () async {
    final token = _fakeJwt({'sub': 'user-1', 'tenantId': 'tenant-42', 'role': 'owner'});
    final dio = Dio(BaseOptions(baseUrl: 'https://cp.example.com'))
      ..httpClientAdapter = FakeHttpClientAdapter(
        (options) => jsonResponseBody({
          'accessToken': token,
          'user': {'id': 'user-1', 'email': 'owner@example.com', 'createdAt': '2026-01-01T00:00:00.000Z'},
        }),
      );
    final api = ControlPlaneAuthApi(ControlPlaneApiClient(dio: dio));

    final result = await api.login(baseUrl: 'https://cp.example.com', email: 'owner@example.com', password: 'x');

    final session = result.fold(onSuccess: (s) => s, onFailure: (_) => null);
    expect(session, isNotNull);
    expect(session!.accessToken, token);
    expect(session.tenantId, 'tenant-42');
    expect(session.userEmail, 'owner@example.com');
    expect(session.baseUrl, 'https://cp.example.com');
  });

  test('login() maps a 401 (wrong email/password) to a Failure with UnauthorizedException', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://cp.example.com'))
      ..httpClientAdapter = FakeHttpClientAdapter(
        (_) => jsonResponseBody({'message': 'Invalid email or password'}, statusCode: 401),
      );
    final api = ControlPlaneAuthApi(ControlPlaneApiClient(dio: dio));

    final result = await api.login(baseUrl: 'https://cp.example.com', email: 'x@example.com', password: 'wrong');

    final error = result.fold(onSuccess: (_) => null, onFailure: (e) => e);
    expect(error, isA<UnauthorizedException>());
  });
}
