import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pterodactyl_mobile/app/app_provider_policy.dart';
import 'package:pterodactyl_mobile/core/error/app_exception.dart';
import 'package:pterodactyl_mobile/core/network/interceptors/auth_interceptor.dart';
import 'package:pterodactyl_mobile/features/control_plane/application/control_plane_network_providers.dart';
import 'package:pterodactyl_mobile/features/control_plane/application/control_plane_servers_providers.dart';
import 'package:pterodactyl_mobile/features/control_plane/application/control_plane_session_controller.dart';
import 'package:pterodactyl_mobile/features/control_plane/data/control_plane_api_client.dart';
import 'package:pterodactyl_mobile/features/control_plane/data/control_plane_api_client_factory.dart';
import 'package:pterodactyl_mobile/features/control_plane/domain/control_plane_session.dart';
import 'package:pterodactyl_mobile/features/control_plane/domain/control_plane_session_storage.dart';

import '../../../support/fake_http_client_adapter.dart';

class _FakeSessionStorage implements ControlPlaneSessionStorage {
  ControlPlaneSession? _stored;

  @override
  Future<void> save(ControlPlaneSession session) async => _stored = session;

  @override
  Future<ControlPlaneSession?> read() async => _stored;

  @override
  Future<void> delete() async => _stored = null;
}

class _FakeControlPlaneApiClientFactory extends ControlPlaneApiClientFactory {
  _FakeControlPlaneApiClientFactory(this.handler);

  final FutureOr<ResponseBody> Function(RequestOptions) handler;

  @override
  ControlPlaneApiClient createFor({required String baseUrl, required AuthTokenProvider authTokenProvider}) {
    final dio = Dio(BaseOptions(baseUrl: baseUrl))..httpClientAdapter = FakeHttpClientAdapter(handler);
    return ControlPlaneApiClient(dio: dio);
  }
}

const _session = ControlPlaneSession(
  baseUrl: 'https://cp.example.com',
  accessToken: 'token',
  tenantId: 't-1',
  userEmail: 'a@example.com',
);

Map<String, dynamic> _serverRow(String id) => {
      'id': id,
      'tenantId': 't-1',
      'instanceId': 'inst-1',
      'pterodactylId': 1,
      'pterodactylUuid': 'uuid-$id',
      'identifier': 'd3aac$id',
      'name': 'Server $id',
      'nodeId': 1,
      'lastSyncedAt': '2026-08-16T12:00:00.000Z',
      'createdAt': '2026-08-16T10:00:00.000Z',
    };

Future<ProviderContainer> _loggedInContainer(FutureOr<ResponseBody> Function(RequestOptions) handler) async {
  final storage = _FakeSessionStorage();
  await storage.save(_session);
  final container = ProviderContainer(
    retry: noAutomaticProviderRetry,
    overrides: [
      controlPlaneSessionStorageProvider.overrideWithValue(storage),
      controlPlaneApiClientFactoryProvider.overrideWithValue(_FakeControlPlaneApiClientFactory(handler)),
    ],
  );
  addTearDown(container.dispose);
  await container.read(controlPlaneSessionControllerProvider.future);
  return container;
}

void main() {
  group('controlPlaneServersApiProvider', () {
    test('throws StateError when read without an active session', () {
      final container = ProviderContainer(
        retry: noAutomaticProviderRetry,
        overrides: [controlPlaneSessionStorageProvider.overrideWithValue(_FakeSessionStorage())],
      );
      addTearDown(container.dispose);

      // Riverpod wraps the thrown StateError in a ProviderException when a
      // failed provider is read — match on the underlying message rather
      // than the exact exception type (same pattern as
      // `instance_api_client_provider_test.dart`).
      expect(
        () => container.read(controlPlaneServersApiProvider),
        throwsA(predicate<Object>((e) => e.toString().contains('read without an active Control Plane session'))),
      );
    });
  });

  group('ControlPlaneServersController', () {
    test('build() loads the server list for the current session', () async {
      final container = await _loggedInContainer((_) => jsonResponseBody([_serverRow('1'), _serverRow('2')]));

      final servers = await container.read(controlPlaneServersControllerProvider.future);

      expect(servers, hasLength(2));
      expect(servers.map((s) => s.id), ['1', '2']);
    });

    test('build() surfaces a server-side failure as AsyncError, not a crash', () async {
      final container = await _loggedInContainer((_) => jsonResponseBody({}, statusCode: 500));

      await expectLater(container.read(controlPlaneServersControllerProvider.future), throwsA(isA<ServerException>()));
    });

    test('refresh() re-fetches and replaces the list', () async {
      var call = 0;
      final container = await _loggedInContainer((_) {
        call++;
        return jsonResponseBody(call == 1 ? [_serverRow('1')] : [_serverRow('1'), _serverRow('2')]);
      });
      await container.read(controlPlaneServersControllerProvider.future);

      await container.read(controlPlaneServersControllerProvider.notifier).refresh();

      final servers = container.read(controlPlaneServersControllerProvider).value;
      expect(servers, hasLength(2));
    });
  });
}
