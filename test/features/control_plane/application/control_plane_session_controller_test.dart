import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pterodactyl_mobile/app/app_provider_policy.dart';
import 'package:pterodactyl_mobile/core/error/app_exception.dart';
import 'package:pterodactyl_mobile/core/network/interceptors/auth_interceptor.dart';
import 'package:pterodactyl_mobile/features/control_plane/application/control_plane_network_providers.dart';
import 'package:pterodactyl_mobile/features/control_plane/application/control_plane_session_controller.dart';
import 'package:pterodactyl_mobile/features/control_plane/data/control_plane_api_client.dart';
import 'package:pterodactyl_mobile/features/control_plane/data/control_plane_api_client_factory.dart';
import 'package:pterodactyl_mobile/features/control_plane/domain/control_plane_session.dart';
import 'package:pterodactyl_mobile/features/control_plane/domain/control_plane_session_storage.dart';

import '../../../support/fake_http_client_adapter.dart';

String _fakeJwt(Map<String, dynamic> payload) {
  final header = base64Url.encode(utf8.encode(jsonEncode({'alg': 'HS256'}))).replaceAll('=', '');
  final body = base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '');
  return '$header.$body.sig';
}

class _FakeSessionStorage implements ControlPlaneSessionStorage {
  ControlPlaneSession? _stored;

  @override
  Future<void> save(ControlPlaneSession session) async => _stored = session;

  @override
  Future<ControlPlaneSession?> read() async => _stored;

  @override
  Future<void> delete() async => _stored = null;
}

/// Routes every request through [handler] regardless of the requested
/// `baseUrl` — this test only ever talks to one backend at a time, so
/// there is no need to distinguish clients by URL the way
/// `instance_api_client_provider_test.dart` does for multiple real panels.
class _FakeControlPlaneApiClientFactory extends ControlPlaneApiClientFactory {
  _FakeControlPlaneApiClientFactory(this.handler);

  final FutureOr<ResponseBody> Function(RequestOptions) handler;

  @override
  ControlPlaneApiClient createFor({required String baseUrl, required AuthTokenProvider authTokenProvider}) {
    final dio = Dio(BaseOptions(baseUrl: baseUrl))..httpClientAdapter = FakeHttpClientAdapter(handler);
    return ControlPlaneApiClient(dio: dio);
  }
}

ProviderContainer _buildContainer({
  required ControlPlaneSessionStorage sessionStorage,
  ControlPlaneApiClientFactory? apiClientFactory,
}) {
  final container = ProviderContainer(
    retry: noAutomaticProviderRetry,
    overrides: [
      controlPlaneSessionStorageProvider.overrideWithValue(sessionStorage),
      if (apiClientFactory != null) controlPlaneApiClientFactoryProvider.overrideWithValue(apiClientFactory),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('ControlPlaneSessionController.build', () {
    test('starts with whatever session is already in storage', () async {
      final storage = _FakeSessionStorage();
      const existing = ControlPlaneSession(
        baseUrl: 'https://cp.example.com',
        accessToken: 'token',
        tenantId: 't-1',
        userEmail: 'a@example.com',
      );
      await storage.save(existing);

      final container = _buildContainer(sessionStorage: storage);
      final session = await container.read(controlPlaneSessionControllerProvider.future);

      expect(session, existing);
    });

    test('starts with null when nothing is stored', () async {
      final container = _buildContainer(sessionStorage: _FakeSessionStorage());
      final session = await container.read(controlPlaneSessionControllerProvider.future);

      expect(session, isNull);
    });
  });

  group('ControlPlaneSessionController.login', () {
    test('on success, persists the session, updates state, and returns null', () async {
      final token = _fakeJwt({'tenantId': 't-42'});
      final storage = _FakeSessionStorage();
      final container = _buildContainer(
        sessionStorage: storage,
        apiClientFactory: _FakeControlPlaneApiClientFactory(
          (_) => jsonResponseBody({
            'accessToken': token,
            'user': {'id': 'u-1', 'email': 'owner@example.com', 'createdAt': '2026-01-01T00:00:00.000Z'},
          }),
        ),
      );
      await container.read(controlPlaneSessionControllerProvider.future);

      final error = await container.read(controlPlaneSessionControllerProvider.notifier).login(
            baseUrl: 'https://cp.example.com/',
            email: 'owner@example.com',
            password: 'password123',
          );

      expect(error, isNull);
      final state = container.read(controlPlaneSessionControllerProvider).value;
      expect(state?.tenantId, 't-42');
      expect(state?.userEmail, 'owner@example.com');
      final persisted = await storage.read();
      expect(persisted?.tenantId, 't-42');
    });

    test('on failure, does not change state and returns the AppException', () async {
      final storage = _FakeSessionStorage();
      final container = _buildContainer(
        sessionStorage: storage,
        apiClientFactory: _FakeControlPlaneApiClientFactory(
          (_) => jsonResponseBody({'message': 'Invalid email or password'}, statusCode: 401),
        ),
      );
      await container.read(controlPlaneSessionControllerProvider.future);

      final error = await container.read(controlPlaneSessionControllerProvider.notifier).login(
            baseUrl: 'https://cp.example.com',
            email: 'owner@example.com',
            password: 'wrong',
          );

      expect(error, isA<UnauthorizedException>());
      expect(container.read(controlPlaneSessionControllerProvider).value, isNull);
      expect(await storage.read(), isNull);
    });
  });

  group('ControlPlaneSessionController.logout', () {
    test('clears both storage and state', () async {
      final storage = _FakeSessionStorage();
      await storage.save(
        const ControlPlaneSession(
          baseUrl: 'https://cp.example.com',
          accessToken: 'token',
          tenantId: 't-1',
          userEmail: 'a@example.com',
        ),
      );
      final container = _buildContainer(sessionStorage: storage);
      await container.read(controlPlaneSessionControllerProvider.future);

      await container.read(controlPlaneSessionControllerProvider.notifier).logout();

      expect(container.read(controlPlaneSessionControllerProvider).value, isNull);
      expect(await storage.read(), isNull);
    });
  });
}
