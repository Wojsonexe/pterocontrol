import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pterodactyl_mobile/app/app_provider_policy.dart';
import 'package:pterodactyl_mobile/app/lifecycle/app_lifecycle_controller.dart';
import 'package:pterodactyl_mobile/core/error/app_exception.dart';
import 'package:pterodactyl_mobile/features/servers/application/server_list_controller.dart';
import 'package:pterodactyl_mobile/features/servers/application/server_list_state.dart';
import 'package:pterodactyl_mobile/features/servers/application/server_runtime_sync_controller.dart';
import 'package:pterodactyl_mobile/features/servers/application/server_runtime_sync_state.dart';
import 'package:pterodactyl_mobile/features/servers/application/servers_providers.dart';
import 'package:pterodactyl_mobile/features/servers/domain/server.dart';
import 'package:pterodactyl_mobile/features/servers/domain/server_page.dart';
import 'package:pterodactyl_mobile/features/servers/domain/server_power_action.dart';
import 'package:pterodactyl_mobile/features/servers/domain/server_power_state.dart';
import 'package:pterodactyl_mobile/features/servers/domain/server_repository.dart';
import 'package:pterodactyl_mobile/features/servers/domain/server_runtime_state.dart';

const _instanceId = 'instance-a';

Server _server(String id, {ServerAdministrativeStatus status = ServerAdministrativeStatus.active}) => Server(
      identifier: id,
      uuid: 'uuid-$id',
      name: 'Server $id',
      node: 'Node 1',
      status: status,
      isTransferring: false,
      limits: const ServerLimits(memoryMb: 512, diskMb: 1024, cpuPercent: 100),
    );

class _FakeServerRepository implements ServerRepository {
  _FakeServerRepository({this.resourceUsageByIdentifier = const {}, this.failingIdentifiers = const {}});

  Map<String, ServerRuntimeState> resourceUsageByIdentifier;
  final Set<String> failingIdentifiers;

  /// If a server's identifier is a key here, [getResourceUsage] waits on
  /// this [Completer] instead of resolving immediately — lets a test hold
  /// one server's request open while asserting on another's.
  final Map<String, Completer<void>> gatedIdentifiers = {};

  int getResourceUsageCallCount = 0;
  final List<String> getServerCalls = [];
  final List<String> resolvedOrder = [];

  @override
  Future<ServerPage> getServers({int page = 1}) async => const ServerPage(servers: [], page: 1, totalPages: 1);

  @override
  Future<void> sendPowerAction(String serverIdentifier, ServerPowerAction action) async {
    throw UnimplementedError('not exercised by these tests');
  }

  @override
  Future<Server> getServer(String serverIdentifier) async {
    getServerCalls.add(serverIdentifier);
    return _server(serverIdentifier);
  }

  @override
  Future<ServerRuntimeState> getResourceUsage(String serverIdentifier) async {
    getResourceUsageCallCount++;
    final gate = gatedIdentifiers[serverIdentifier];
    if (gate != null) await gate.future;
    resolvedOrder.add(serverIdentifier);
    if (failingIdentifiers.contains(serverIdentifier)) throw const ServerException();
    return resourceUsageByIdentifier[serverIdentifier] ?? ServerRuntimeState.unknown;
  }
}

/// Serves a fixed [ServerListState] instead of fetching from a repository —
/// isolates these tests from `ServerListController.build`'s own behavior
/// (covered by `server_list_controller_test.dart`) while still exercising
/// the real [ServerListController.refreshOne] that
/// `ServerRuntimeSyncController` calls for transitional servers.
class _FixedServerListController extends ServerListController {
  _FixedServerListController(this._initial) : super(_instanceId);

  final ServerListState _initial;

  @override
  Future<ServerListState> build() async => _initial;
}

ProviderContainer _buildContainer({
  required ServerRepository repository,
  required List<Server> servers,
}) {
  final container = ProviderContainer(
    retry: noAutomaticProviderRetry,
    overrides: [
      serverRepositoryProvider(_instanceId).overrideWithValue(repository),
      serverListControllerProvider(_instanceId).overrideWith(
        () => _FixedServerListController(ServerListState(servers: servers, page: 1, totalPages: 1)),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ServerRuntimeSyncController', () {
    test('polls getResourceUsage for every currently loaded server immediately on build', () async {
      final repository = _FakeServerRepository(
        resourceUsageByIdentifier: {
          'a': const ServerRuntimeState(powerState: ServerPowerState.running, cpuAbsolutePercent: 10),
          'b': const ServerRuntimeState(powerState: ServerPowerState.offline),
        },
      );
      final container = _buildContainer(repository: repository, servers: [_server('a'), _server('b')]);
      await container.read(serverListControllerProvider(_instanceId).future);

      final subscription = container.listen(serverRuntimeSyncControllerProvider(_instanceId), (_, _) {});
      addTearDown(subscription.close);
      await pumpEventQueue();

      expect(repository.getResourceUsageCallCount, 2);
      final state = container.read(serverRuntimeSyncControllerProvider(_instanceId));
      expect(state.status, ServerSyncStatus.live);
      expect(state.runtimeFor('a')?.powerState, ServerPowerState.running);
      expect(state.runtimeFor('b')?.powerState, ServerPowerState.offline);
    });

    test('reports offline when every poll fails, but keeps the last known readings', () async {
      final repository = _FakeServerRepository(failingIdentifiers: {'a'});
      final container = _buildContainer(repository: repository, servers: [_server('a')]);
      await container.read(serverListControllerProvider(_instanceId).future);

      final subscription = container.listen(serverRuntimeSyncControllerProvider(_instanceId), (_, _) {});
      addTearDown(subscription.close);
      await pumpEventQueue();

      final state = container.read(serverRuntimeSyncControllerProvider(_instanceId));
      expect(state.status, ServerSyncStatus.offline);
    });

    test('does not poll when the app is not visible at build time', () async {
      final repository = _FakeServerRepository();
      final container = _buildContainer(repository: repository, servers: [_server('a')]);
      await container.read(serverListControllerProvider(_instanceId).future);
      container.read(appLifecycleControllerProvider.notifier).state = AppLifecycleState.paused;

      final subscription = container.listen(serverRuntimeSyncControllerProvider(_instanceId), (_, _) {});
      addTearDown(subscription.close);
      await pumpEventQueue();

      expect(repository.getResourceUsageCallCount, 0);
      expect(container.read(serverRuntimeSyncControllerProvider(_instanceId)).status, ServerSyncStatus.syncing);
    });

    test('polls immediately when the app returns to the foreground', () async {
      final repository = _FakeServerRepository();
      final container = _buildContainer(repository: repository, servers: [_server('a')]);
      await container.read(serverListControllerProvider(_instanceId).future);
      container.read(appLifecycleControllerProvider.notifier).state = AppLifecycleState.paused;

      final subscription = container.listen(serverRuntimeSyncControllerProvider(_instanceId), (_, _) {});
      addTearDown(subscription.close);
      await pumpEventQueue();
      expect(repository.getResourceUsageCallCount, 0);

      container.read(appLifecycleControllerProvider.notifier).state = AppLifecycleState.resumed;
      await pumpEventQueue();

      expect(repository.getResourceUsageCallCount, 1);
      expect(container.read(serverRuntimeSyncControllerProvider(_instanceId)).status, ServerSyncStatus.live);
    });

    test(
      'accumulates real samples into history, computing a network rate only once a previous sample exists',
      () async {
        final t0 = DateTime(2026, 1, 1, 12, 0, 0);
        final repository = _FakeServerRepository(
          resourceUsageByIdentifier: {
            'a': ServerRuntimeState(
              powerState: ServerPowerState.running,
              observedAt: t0,
              cpuAbsolutePercent: 10,
              memoryBytes: 1000,
              networkRxBytes: 1000,
              networkTxBytes: 500,
            ),
          },
        );
        final container = _buildContainer(repository: repository, servers: [_server('a')]);
        await container.read(serverListControllerProvider(_instanceId).future);

        final subscription = container.listen(serverRuntimeSyncControllerProvider(_instanceId), (_, _) {});
        addTearDown(subscription.close);
        await pumpEventQueue();

        var history = container.read(serverRuntimeSyncControllerProvider(_instanceId)).historyFor('a');
        expect(history.samples, hasLength(1));
        expect(
          history.latest?.networkRxRateBytesPerSecond,
          isNull,
          reason: 'no previous sample to diff against on the very first reading',
        );
        expect(history.latest?.cpuPercent, 10);

        // Second tick, 10 (simulated) seconds later: rx grew by 2000
        // bytes, tx by 1000 — real deltas over real elapsed time, not
        // fabricated.
        repository.resourceUsageByIdentifier = {
          'a': ServerRuntimeState(
            powerState: ServerPowerState.running,
            observedAt: t0.add(const Duration(seconds: 10)),
            cpuAbsolutePercent: 20,
            memoryBytes: 1200,
            networkRxBytes: 3000,
            networkTxBytes: 1500,
          ),
        };
        container.read(appLifecycleControllerProvider.notifier).state = AppLifecycleState.paused;
        await pumpEventQueue();
        container.read(appLifecycleControllerProvider.notifier).state = AppLifecycleState.resumed;
        await pumpEventQueue();

        history = container.read(serverRuntimeSyncControllerProvider(_instanceId)).historyFor('a');
        expect(history.samples, hasLength(2));
        expect(history.cpuSeries, [10.0, 20.0]);
        expect(history.latest?.networkRxRateBytesPerSecond, closeTo(200, 0.01), reason: '2000 bytes / 10s = 200 B/s');
        expect(history.latest?.networkTxRateBytesPerSecond, closeTo(100, 0.01), reason: '1000 bytes / 10s = 100 B/s');
      },
    );

    test(
      'refreshes the administrative status of servers still installing or restoring a backup',
      () async {
        final repository = _FakeServerRepository();
        final container = _buildContainer(
          repository: repository,
          servers: [
            _server('installing', status: ServerAdministrativeStatus.installing),
            _server('restoring', status: ServerAdministrativeStatus.restoringBackup),
            _server('active', status: ServerAdministrativeStatus.active),
          ],
        );
        await container.read(serverListControllerProvider(_instanceId).future);

        final subscription = container.listen(serverRuntimeSyncControllerProvider(_instanceId), (_, _) {});
        addTearDown(subscription.close);
        await pumpEventQueue();

        expect(
          repository.getServerCalls,
          unorderedEquals(['installing', 'restoring']),
          reason: 'only transitional servers should trigger the extra administrative-status fetch',
        );
      },
    );

    test('a slow server does not delay another server\'s reading from reaching state', () async {
      final gate = Completer<void>();
      final repository = _FakeServerRepository(
        resourceUsageByIdentifier: {
          'fast': const ServerRuntimeState(powerState: ServerPowerState.running, cpuAbsolutePercent: 5),
          'slow': const ServerRuntimeState(powerState: ServerPowerState.running, cpuAbsolutePercent: 99),
        },
      )..gatedIdentifiers['slow'] = gate;
      final container = _buildContainer(repository: repository, servers: [_server('fast'), _server('slow')]);
      await container.read(serverListControllerProvider(_instanceId).future);

      final subscription = container.listen(serverRuntimeSyncControllerProvider(_instanceId), (_, _) {});
      addTearDown(subscription.close);
      await pumpEventQueue();

      // 'slow' is still gated — its own request hasn't resolved — but
      // 'fast' must already be applied, independently.
      var state = container.read(serverRuntimeSyncControllerProvider(_instanceId));
      expect(state.runtimeFor('fast')?.cpuAbsolutePercent, 5, reason: 'fast server must not wait for the slow one');
      expect(state.runtimeFor('slow'), isNull);
      expect(state.isRefreshing('slow'), isTrue);

      gate.complete();
      await pumpEventQueue();

      state = container.read(serverRuntimeSyncControllerProvider(_instanceId));
      expect(state.runtimeFor('slow')?.cpuAbsolutePercent, 99);
      expect(state.isRefreshing('slow'), isFalse);
    });

    test('a refresh in progress keeps showing the previous reading, not a blank state', () async {
      final repository = _FakeServerRepository(
        resourceUsageByIdentifier: {
          'a': const ServerRuntimeState(powerState: ServerPowerState.running, cpuAbsolutePercent: 42),
        },
      );
      final container = _buildContainer(repository: repository, servers: [_server('a')]);
      await container.read(serverListControllerProvider(_instanceId).future);

      final subscription = container.listen(serverRuntimeSyncControllerProvider(_instanceId), (_, _) {});
      addTearDown(subscription.close);
      await pumpEventQueue();
      expect(container.read(serverRuntimeSyncControllerProvider(_instanceId)).runtimeFor('a')?.cpuAbsolutePercent, 42);

      // Second tick: gate 'a' so its request stays in flight, and force
      // the tick via the same foreground-resume mechanism the controller
      // tests above already use.
      final gate = Completer<void>();
      repository.gatedIdentifiers['a'] = gate;
      container.read(appLifecycleControllerProvider.notifier).state = AppLifecycleState.paused;
      await pumpEventQueue();
      container.read(appLifecycleControllerProvider.notifier).state = AppLifecycleState.resumed;
      await pumpEventQueue();

      final mid = container.read(serverRuntimeSyncControllerProvider(_instanceId));
      expect(mid.isRefreshing('a'), isTrue);
      expect(mid.runtimeFor('a')?.cpuAbsolutePercent, 42, reason: 'stale value must stay visible while refreshing');

      gate.complete();
      await pumpEventQueue();
      expect(container.read(serverRuntimeSyncControllerProvider(_instanceId)).isRefreshing('a'), isFalse);
    });

    test('a failed refresh keeps the last good reading and flags the failure', () async {
      final repository = _FakeServerRepository(
        resourceUsageByIdentifier: {
          'a': const ServerRuntimeState(powerState: ServerPowerState.running, cpuAbsolutePercent: 42),
        },
        failingIdentifiers: <String>{},
      );
      final container = _buildContainer(repository: repository, servers: [_server('a')]);
      await container.read(serverListControllerProvider(_instanceId).future);

      final subscription = container.listen(serverRuntimeSyncControllerProvider(_instanceId), (_, _) {});
      addTearDown(subscription.close);
      await pumpEventQueue();
      expect(container.read(serverRuntimeSyncControllerProvider(_instanceId)).runtimeFor('a')?.cpuAbsolutePercent, 42);

      repository.failingIdentifiers.add('a');
      container.read(appLifecycleControllerProvider.notifier).state = AppLifecycleState.paused;
      await pumpEventQueue();
      container.read(appLifecycleControllerProvider.notifier).state = AppLifecycleState.resumed;
      await pumpEventQueue();

      final state = container.read(serverRuntimeSyncControllerProvider(_instanceId));
      expect(state.hasRecentFailure('a'), isTrue);
      expect(state.isRefreshing('a'), isFalse);
      expect(
        state.runtimeFor('a')?.cpuAbsolutePercent,
        42,
        reason: 'a failed refresh must never clear what was already known',
      );
    });

    test('an out-of-order response with an older observedAt never overwrites a fresher reading', () async {
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);
      final repository = _FakeServerRepository(
        resourceUsageByIdentifier: {
          'a': ServerRuntimeState(powerState: ServerPowerState.running, observedAt: t0, cpuAbsolutePercent: 42),
        },
      );
      final container = _buildContainer(repository: repository, servers: [_server('a')]);
      await container.read(serverListControllerProvider(_instanceId).future);

      final subscription = container.listen(serverRuntimeSyncControllerProvider(_instanceId), (_, _) {});
      addTearDown(subscription.close);
      await pumpEventQueue();
      expect(container.read(serverRuntimeSyncControllerProvider(_instanceId)).runtimeFor('a')?.observedAt, t0);

      // A second tick's response reports an *older* observedAt than what
      // is already stored — network jitter, or (once a second producer
      // such as a WebSocket ever feeds this same state) a slower source
      // resolving after a fresher one already landed.
      repository.resourceUsageByIdentifier = {
        'a': ServerRuntimeState(
          powerState: ServerPowerState.running,
          observedAt: t0.subtract(const Duration(seconds: 5)),
          cpuAbsolutePercent: 999,
        ),
      };
      container.read(appLifecycleControllerProvider.notifier).state = AppLifecycleState.paused;
      await pumpEventQueue();
      container.read(appLifecycleControllerProvider.notifier).state = AppLifecycleState.resumed;
      await pumpEventQueue();

      final state = container.read(serverRuntimeSyncControllerProvider(_instanceId));
      expect(state.runtimeFor('a')?.cpuAbsolutePercent, 42, reason: 'the older reading must not clobber the newer one');
      expect(state.runtimeFor('a')?.observedAt, t0);
    });
  });
}
