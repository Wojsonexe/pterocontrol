import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pterodactyl_mobile/app/app_provider_policy.dart';
import 'package:pterodactyl_mobile/core/error/app_exception.dart';
import 'package:pterodactyl_mobile/core/network/interceptors/auth_interceptor.dart';
import 'package:pterodactyl_mobile/features/control_plane/application/control_plane_network_providers.dart';
import 'package:pterodactyl_mobile/features/control_plane/application/control_plane_server_detail_providers.dart';
import 'package:pterodactyl_mobile/features/control_plane/application/control_plane_session_controller.dart';
import 'package:pterodactyl_mobile/features/control_plane/data/control_plane_api_client.dart';
import 'package:pterodactyl_mobile/features/control_plane/data/control_plane_api_client_factory.dart';
import 'package:pterodactyl_mobile/features/control_plane/domain/control_plane_power_action.dart';
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

Map<String, dynamic> _resourcesJson({String state = 'running'}) => {
      'currentState': state,
      'isSuspended': false,
      'cpuAbsolutePercent': 5.0,
      'memoryBytes': 1000,
      'diskBytes': 2000,
      'networkRxBytes': 10,
      'networkTxBytes': 20,
      'uptimeMs': 60000,
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
  group('controlPlaneResourcesProvider', () {
    test('fetches resource usage for the given server id', () async {
      RequestOptions? captured;
      final container = await _loggedInContainer((options) {
        captured = options;
        return jsonResponseBody(_resourcesJson());
      });

      final usage = await container.read(controlPlaneResourcesProvider('srv-1').future);

      expect(captured!.path, '/servers/srv-1/resources');
      expect(usage.currentState, 'running');
    });
  });

  group('ControlPlanePowerActionController', () {
    test('send() success updates state to the sent action and invalidates the resources provider', () async {
      var resourceFetches = 0;
      final container = await _loggedInContainer((options) {
        if (options.path.endsWith('/power')) return jsonResponseBody({'accepted': true}, statusCode: 202);
        resourceFetches++;
        return jsonResponseBody(_resourcesJson());
      });
      await container.read(controlPlaneResourcesProvider('srv-1').future);
      final fetchesBeforeAction = resourceFetches;
      // This provider is `autoDispose` — production code relies on that to
      // stop tracking a server the moment its detail screen is popped (see
      // `ControlPlanePowerActionController`'s doc comment), but it means a
      // bare `container.read(...)` here (no active listener, just like an
      // unmounted widget) can get disposed mid-`send()`, before the state
      // write happens. A real screen keeps it alive via `ref.watch` while
      // visible; `container.listen` is the test equivalent.
      container.listen(controlPlanePowerActionControllerProvider('srv-1'), (_, _) {});
      // `build()` starts as `AsyncLoading` until its Future resolves;
      // `send()` no-ops while `state.isLoading` (its own in-flight guard),
      // so the initial build must be awaited first or `send` below would
      // silently do nothing.
      await container.read(controlPlanePowerActionControllerProvider('srv-1').future);

      await container.read(controlPlanePowerActionControllerProvider('srv-1').notifier).send(ControlPlanePowerAction.restart);

      final state = container.read(controlPlanePowerActionControllerProvider('srv-1'));
      expect(state.value, ControlPlanePowerAction.restart);
      // Invalidating the resources provider does not force a re-fetch until
      // something reads it again — re-read it here to prove it was actually
      // invalidated rather than serving a stale cached value.
      await container.read(controlPlaneResourcesProvider('srv-1').future);
      expect(resourceFetches, greaterThan(fetchesBeforeAction));
    });

    test('send() failure surfaces as AsyncError without changing to the attempted action', () async {
      final container = await _loggedInContainer((options) {
        if (options.path.endsWith('/power')) return jsonResponseBody({}, statusCode: 403);
        return jsonResponseBody(_resourcesJson());
      });

      container.listen(controlPlanePowerActionControllerProvider('srv-1'), (_, _) {});
      await container.read(controlPlanePowerActionControllerProvider('srv-1').future);
      await container.read(controlPlanePowerActionControllerProvider('srv-1').notifier).send(ControlPlanePowerAction.stop);

      final state = container.read(controlPlanePowerActionControllerProvider('srv-1'));
      expect(state.hasError, isTrue);
      expect(state.error, isA<ForbiddenException>());
    });
  });
}
