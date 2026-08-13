import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pterodactyl_mobile/app/app_provider_policy.dart';
import 'package:pterodactyl_mobile/core/error/app_exception.dart';
import 'package:pterodactyl_mobile/features/servers/application/server_list_controller.dart';
import 'package:pterodactyl_mobile/features/servers/application/server_power_action_controller.dart';
import 'package:pterodactyl_mobile/features/servers/application/servers_providers.dart';
import 'package:pterodactyl_mobile/features/servers/domain/server.dart';
import 'package:pterodactyl_mobile/features/servers/domain/server_page.dart';
import 'package:pterodactyl_mobile/features/servers/domain/server_power_action.dart';
import 'package:pterodactyl_mobile/features/servers/domain/server_repository.dart';
import 'package:pterodactyl_mobile/features/servers/domain/server_runtime_state.dart';

class _FakeServerRepository implements ServerRepository {
  _FakeServerRepository({this.powerError});

  AppException? powerError;
  int powerActionCallCount = 0;
  int getServersCallCount = 0;
  ServerPowerAction? lastAction;
  String? lastServerIdentifier;

  @override
  Future<ServerPage> getServers({int page = 1}) async {
    getServersCallCount++;
    return const ServerPage(servers: [], page: 1, totalPages: 1);
  }

  @override
  Future<void> sendPowerAction(String serverIdentifier, ServerPowerAction action) async {
    powerActionCallCount++;
    lastAction = action;
    lastServerIdentifier = serverIdentifier;
    if (powerError != null) throw powerError!;
  }

  @override
  Future<Server> getServer(String serverIdentifier) async {
    throw UnimplementedError('not exercised by this controller test');
  }

  @override
  Future<ServerRuntimeState> getResourceUsage(String serverIdentifier) async => ServerRuntimeState.unknown;
}

/// A repository whose `sendPowerAction` blocks on [gate] — used to test
/// that a second `send()` call is ignored while the first is in flight.
class _ControlledServerRepository implements ServerRepository {
  _ControlledServerRepository(this.gate);

  final Completer<void> gate;
  int callCount = 0;

  @override
  Future<ServerPage> getServers({int page = 1}) async => const ServerPage(servers: [], page: 1, totalPages: 1);

  @override
  Future<void> sendPowerAction(String serverIdentifier, ServerPowerAction action) async {
    callCount++;
    await gate.future;
  }

  @override
  Future<Server> getServer(String serverIdentifier) async {
    throw UnimplementedError('not exercised by this controller test');
  }

  @override
  Future<ServerRuntimeState> getResourceUsage(String serverIdentifier) async => ServerRuntimeState.unknown;
}

/// Builds a container wired with [repositoriesByInstance] and — critically
/// for providers that are `autoDispose` — keeps every provider in
/// [keepAliveTargets] alive for the container's lifetime.
///
/// Without this, `container.read(provider)` alone does *not* keep an
/// `autoDispose` provider alive across an `await` gap (unlike `ref.watch`
/// inside a widget, which is what keeps these providers alive in the real
/// app — `ServerPowerActions` watches `serverPowerActionControllerProvider`,
/// and `ServerDetailScreen` watches `serverListControllerProvider`). A test
/// that only ever `read`s would see the provider torn down and silently
/// recreated between statements, which is what a `container.listen` (a
/// no-op listener, exactly mirroring what a widget's `watch` does)
/// prevents.
ProviderContainer _buildContainer(
  Map<String, ServerRepository> repositoriesByInstance, {
  List<ServerActionTarget> keepAliveTargets = const [],
}) {
  final container = ProviderContainer(
    retry: noAutomaticProviderRetry,
    overrides: [
      for (final entry in repositoriesByInstance.entries)
        serverRepositoryProvider(entry.key).overrideWithValue(entry.value),
    ],
  );
  addTearDown(container.dispose);
  for (final target in keepAliveTargets) {
    container.listen(serverPowerActionControllerProvider(target), (_, _) {});
    container.listen(serverListControllerProvider(target.instanceId), (_, _) {});
  }
  return container;
}

void main() {
  group('ServerPowerActionController.build', () {
    test('starts idle — no action performed yet', () async {
      const target = (instanceId: 'instance-a', serverIdentifier: 'srv-1');
      final container = _buildContainer({'instance-a': _FakeServerRepository()}, keepAliveTargets: [target]);

      final result = await container.read(serverPowerActionControllerProvider(target).future);

      expect(result, isNull);
    });
  });

  group('ServerPowerActionController.send — success', () {
    test('calls the repository with the right server/action and refreshes the server list', () async {
      const target = (instanceId: 'instance-a', serverIdentifier: 'srv-1');
      final repository = _FakeServerRepository();
      final container = _buildContainer({'instance-a': repository}, keepAliveTargets: [target]);

      await container.read(serverPowerActionControllerProvider(target).future);
      await container.read(serverListControllerProvider(target.instanceId).future);
      final getServersCallsBefore = repository.getServersCallCount;

      await container.read(serverPowerActionControllerProvider(target).notifier).send(ServerPowerAction.restart);

      expect(repository.lastServerIdentifier, 'srv-1');
      expect(repository.lastAction, ServerPowerAction.restart);
      expect(
        container.read(serverPowerActionControllerProvider(target)).value,
        ServerPowerAction.restart,
      );
      expect(
        repository.getServersCallCount,
        getServersCallsBefore + 1,
        reason: 'a successful action must trigger exactly one server-list refresh',
      );
    });
  });

  group('ServerPowerActionController.send — failure', () {
    test('surfaces the error and does not refresh the server list', () async {
      const target = (instanceId: 'instance-a', serverIdentifier: 'srv-1');
      final repository = _FakeServerRepository(powerError: const ForbiddenException());
      final container = _buildContainer({'instance-a': repository}, keepAliveTargets: [target]);

      await container.read(serverPowerActionControllerProvider(target).future);
      await container.read(serverListControllerProvider(target.instanceId).future);
      final getServersCallsBefore = repository.getServersCallCount;

      await container.read(serverPowerActionControllerProvider(target).notifier).send(ServerPowerAction.kill);

      final state = container.read(serverPowerActionControllerProvider(target));
      expect(state.hasError, isTrue);
      expect(state.error, isA<ForbiddenException>());
      expect(
        repository.getServersCallCount,
        getServersCallsBefore,
        reason: 'a failed action must not trigger a list refresh',
      );
    });
  });

  group('ServerPowerActionController.send — in-flight guard', () {
    test('a second send() call is ignored while the first is still in flight', () async {
      const target = (instanceId: 'instance-a', serverIdentifier: 'srv-1');
      final gate = Completer<void>();
      final repository = _ControlledServerRepository(gate);
      final container = _buildContainer({'instance-a': repository}, keepAliveTargets: [target]);
      await container.read(serverPowerActionControllerProvider(target).future);

      final notifier = container.read(serverPowerActionControllerProvider(target).notifier);
      final firstSend = notifier.send(ServerPowerAction.start);
      await Future<void>.delayed(Duration.zero); // let send() reach the `await gate.future` point

      expect(container.read(serverPowerActionControllerProvider(target)).isLoading, isTrue);

      await notifier.send(ServerPowerAction.stop); // should be a no-op — first call still pending

      expect(repository.callCount, 1, reason: 'the repository must only have been called once so far');

      gate.complete();
      await firstSend;
    });
  });

  group('ServerPowerActionController — disposal during an in-flight operation', () {
    test('send() does not throw when the container is disposed while it is in flight', () async {
      const target = (instanceId: 'instance-a', serverIdentifier: 'srv-1');
      final gate = Completer<void>();
      final repository = _ControlledServerRepository(gate);
      final container = ProviderContainer(
        retry: noAutomaticProviderRetry,
        overrides: [serverRepositoryProvider('instance-a').overrideWithValue(repository)],
      );
      container.listen(serverPowerActionControllerProvider(target), (_, _) {});
      await container.read(serverPowerActionControllerProvider(target).future);

      final sendFuture = container.read(serverPowerActionControllerProvider(target).notifier).send(
            ServerPowerAction.start,
          );
      await Future<void>.delayed(Duration.zero); // let send() reach the blocked repository call

      container.dispose(); // simulate leaving the screen mid-request

      gate.complete();

      await expectLater(sendFuture, completes);
    });
  });

  group('ServerPowerActionController — instance isolation', () {
    test('actions for different instances use different repositories and never share state', () async {
      const targetA = (instanceId: 'instance-a', serverIdentifier: 'srv-1');
      // Same serverIdentifier as targetA, deliberately, to prove isolation
      // comes from instanceId, not from the server id happening to differ.
      const targetB = (instanceId: 'instance-b', serverIdentifier: 'srv-1');

      final repositoryA = _FakeServerRepository();
      final repositoryB = _FakeServerRepository();
      final container = _buildContainer(
        {'instance-a': repositoryA, 'instance-b': repositoryB},
        keepAliveTargets: [targetA, targetB],
      );

      await container.read(serverPowerActionControllerProvider(targetA).future);
      await container.read(serverPowerActionControllerProvider(targetB).future);
      await container.read(serverListControllerProvider('instance-a').future);
      await container.read(serverListControllerProvider('instance-b').future);

      await container.read(serverPowerActionControllerProvider(targetA).notifier).send(ServerPowerAction.start);

      expect(repositoryA.powerActionCallCount, 1);
      expect(
        repositoryB.powerActionCallCount,
        0,
        reason: "instance B's repository must never see an action meant for instance A",
      );
      expect(container.read(serverPowerActionControllerProvider(targetA)).value, ServerPowerAction.start);
      expect(
        container.read(serverPowerActionControllerProvider(targetB)).value,
        isNull,
        reason: "instance B's action state must be untouched by instance A's action",
      );
    });
  });
}
