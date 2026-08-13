import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pterodactyl_mobile/app/app_provider_policy.dart';
import 'package:pterodactyl_mobile/core/error/app_exception.dart';
import 'package:pterodactyl_mobile/features/servers/application/server_list_controller.dart';
import 'package:pterodactyl_mobile/features/servers/application/servers_providers.dart';
import 'package:pterodactyl_mobile/features/servers/domain/server.dart';
import 'package:pterodactyl_mobile/features/servers/domain/server_page.dart';
import 'package:pterodactyl_mobile/features/servers/domain/server_power_action.dart';
import 'package:pterodactyl_mobile/features/servers/domain/server_repository.dart';
import 'package:pterodactyl_mobile/features/servers/domain/server_runtime_state.dart';

const _instanceId = 'instance-a';

Server _server(String id, {String? name}) => Server(
      identifier: id,
      uuid: 'uuid-$id',
      name: name ?? 'Server $id',
      node: 'Node 1',
      status: ServerAdministrativeStatus.active,
      isTransferring: false,
      limits: const ServerLimits(memoryMb: 512, diskMb: 1024, cpuPercent: 100),
    );

class _FakeServerRepository implements ServerRepository {
  _FakeServerRepository({
    this.pages = const {},
    this.errorsByPage = const {},
    this.serversByIdentifier = const {},
    this.getServerErrorsByIdentifier = const {},
  });

  final Map<int, ServerPage> pages;
  final Map<int, AppException> errorsByPage;
  final Map<String, Server> serversByIdentifier;
  final Map<String, AppException> getServerErrorsByIdentifier;
  int callCount = 0;
  int getServerCallCount = 0;

  @override
  Future<ServerPage> getServers({int page = 1}) async {
    callCount++;
    final error = errorsByPage[page];
    if (error != null) throw error;
    final result = pages[page];
    if (result == null) throw StateError('No fixture registered for page $page');
    return result;
  }

  @override
  Future<void> sendPowerAction(String serverIdentifier, ServerPowerAction action) async {
    throw UnimplementedError('not exercised by these tests — see server_power_action_controller_test.dart');
  }

  @override
  Future<Server> getServer(String serverIdentifier) async {
    getServerCallCount++;
    final error = getServerErrorsByIdentifier[serverIdentifier];
    if (error != null) throw error;
    final result = serversByIdentifier[serverIdentifier];
    if (result == null) throw StateError('No fixture registered for server $serverIdentifier');
    return result;
  }

  @override
  Future<ServerRuntimeState> getResourceUsage(String serverIdentifier) async => ServerRuntimeState.unknown;
}

/// A repository whose `getServers` blocks until [gate] completes — used to
/// deterministically control timing around an in-flight request.
class _ControlledServerRepository implements ServerRepository {
  Completer<ServerPage> gate = Completer<ServerPage>();
  int callCount = 0;

  @override
  Future<ServerPage> getServers({int page = 1}) async {
    callCount++;
    return gate.future;
  }

  @override
  Future<void> sendPowerAction(String serverIdentifier, ServerPowerAction action) async {
    throw UnimplementedError('not exercised by these tests');
  }

  @override
  Future<Server> getServer(String serverIdentifier) async {
    throw UnimplementedError('not exercised by these tests');
  }

  @override
  Future<ServerRuntimeState> getResourceUsage(String serverIdentifier) async {
    throw UnimplementedError('not exercised by these tests');
  }
}

ProviderContainer _buildContainer(ServerRepository repository) {
  final container = ProviderContainer(
    retry: noAutomaticProviderRetry,
    overrides: [serverRepositoryProvider(_instanceId).overrideWithValue(repository)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('ServerListController.build', () {
    test('exposes the servers and pagination info from the first page', () async {
      final repository = _FakeServerRepository(
        pages: {1: ServerPage(servers: [_server('a'), _server('b')], page: 1, totalPages: 2)},
      );
      final container = _buildContainer(repository);

      final state = await container.read(serverListControllerProvider(_instanceId).future);

      expect(state.servers.map((s) => s.identifier), ['a', 'b']);
      expect(state.page, 1);
      expect(state.hasNextPage, isTrue);
    });

    test('exposes an empty list when the instance has no servers', () async {
      final repository = _FakeServerRepository(
        pages: {1: const ServerPage(servers: [], page: 1, totalPages: 1)},
      );
      final container = _buildContainer(repository);

      final state = await container.read(serverListControllerProvider(_instanceId).future);

      expect(state.servers, isEmpty);
      expect(state.hasNextPage, isFalse);
    });

    test('surfaces a repository failure as an error state instead of throwing past the provider', () async {
      final repository = _FakeServerRepository(errorsByPage: {1: const ServerException()});
      final container = _buildContainer(repository);

      await expectLater(
        container.read(serverListControllerProvider(_instanceId).future),
        throwsA(isA<ServerException>()),
      );
      expect(container.read(serverListControllerProvider(_instanceId)).hasError, isTrue);
    });
  });

  group('ServerListController.refresh', () {
    test('re-fetches page 1 and replaces the current list', () async {
      final repository = _FakeServerRepository(
        pages: {1: ServerPage(servers: [_server('a')], page: 1, totalPages: 1)},
      );
      final container = _buildContainer(repository);
      await container.read(serverListControllerProvider(_instanceId).future);

      await container.read(serverListControllerProvider(_instanceId).notifier).refresh();

      expect(repository.callCount, 2);
      expect(container.read(serverListControllerProvider(_instanceId)).value?.servers, hasLength(1));
    });
  });

  group('ServerListController.loadNextPage', () {
    test('appends the next page to the existing list', () async {
      final repository = _FakeServerRepository(
        pages: {
          1: ServerPage(servers: [_server('a')], page: 1, totalPages: 2),
          2: ServerPage(servers: [_server('b')], page: 2, totalPages: 2),
        },
      );
      final container = _buildContainer(repository);
      await container.read(serverListControllerProvider(_instanceId).future);

      await container.read(serverListControllerProvider(_instanceId).notifier).loadNextPage();

      final state = container.read(serverListControllerProvider(_instanceId)).value!;
      expect(state.servers.map((s) => s.identifier), ['a', 'b']);
      expect(state.page, 2);
      expect(state.hasNextPage, isFalse);
      expect(state.isLoadingNextPage, isFalse);
    });

    test('is a no-op when there is no next page', () async {
      final repository = _FakeServerRepository(
        pages: {1: ServerPage(servers: [_server('a')], page: 1, totalPages: 1)},
      );
      final container = _buildContainer(repository);
      await container.read(serverListControllerProvider(_instanceId).future);

      await container.read(serverListControllerProvider(_instanceId).notifier).loadNextPage();

      expect(repository.callCount, 1, reason: 'only the initial build() should have called the repository');
    });

    test('keeps the existing list and clears isLoadingNextPage when the next page fails', () async {
      final repository = _FakeServerRepository(
        pages: {1: ServerPage(servers: [_server('a')], page: 1, totalPages: 2)},
        errorsByPage: {2: const ServerException()},
      );
      final container = _buildContainer(repository);
      await container.read(serverListControllerProvider(_instanceId).future);

      await expectLater(
        container.read(serverListControllerProvider(_instanceId).notifier).loadNextPage(),
        throwsA(isA<ServerException>()),
      );

      final state = container.read(serverListControllerProvider(_instanceId)).value!;
      expect(state.servers, hasLength(1), reason: 'a failed load-more must not drop already-loaded servers');
      expect(state.isLoadingNextPage, isFalse);
    });
  });

  group('ServerListController.refreshOne', () {
    test('replaces only the matching server in the loaded list', () async {
      final repository = _FakeServerRepository(
        pages: {
          1: ServerPage(servers: [_server('a'), _server('b')], page: 1, totalPages: 1),
        },
        serversByIdentifier: {'b': _server('b', name: 'Server b (updated)')},
      );
      final container = _buildContainer(repository);
      await container.read(serverListControllerProvider(_instanceId).future);

      await container.read(serverListControllerProvider(_instanceId).notifier).refreshOne('b');

      final state = container.read(serverListControllerProvider(_instanceId)).value!;
      expect(state.servers.map((s) => s.identifier), ['a', 'b']);
      expect(state.servers.firstWhere((s) => s.identifier == 'b').name, 'Server b (updated)');
      expect(repository.getServerCallCount, 1);
    });

    test('is a no-op when the server is not in the currently loaded list', () async {
      final repository = _FakeServerRepository(
        pages: {
          1: ServerPage(servers: [_server('a')], page: 1, totalPages: 1),
        },
      );
      final container = _buildContainer(repository);
      await container.read(serverListControllerProvider(_instanceId).future);

      await container.read(serverListControllerProvider(_instanceId).notifier).refreshOne('missing');

      expect(repository.getServerCallCount, 0);
      expect(container.read(serverListControllerProvider(_instanceId)).value!.servers, hasLength(1));
    });

    test('keeps the stale entry when the fetch fails', () async {
      final repository = _FakeServerRepository(
        pages: {
          1: ServerPage(servers: [_server('a')], page: 1, totalPages: 1),
        },
        getServerErrorsByIdentifier: {'a': const ServerException()},
      );
      final container = _buildContainer(repository);
      await container.read(serverListControllerProvider(_instanceId).future);

      await container.read(serverListControllerProvider(_instanceId).notifier).refreshOne('a');

      final state = container.read(serverListControllerProvider(_instanceId)).value!;
      expect(state.servers.single.identifier, 'a');
      expect(state.servers.single.name, 'Server a', reason: 'a failed refresh must not disturb the stale entry');
    });
  });

  group('ServerListController — autoDispose', () {
    test('is torn down once nothing is watching it, and rebuilds fresh afterward', () async {
      final repository = _FakeServerRepository(
        pages: {1: ServerPage(servers: [_server('a')], page: 1, totalPages: 1)},
      );
      final container = _buildContainer(repository);

      final subscription = container.listen(serverListControllerProvider(_instanceId), (_, _) {});
      await container.read(serverListControllerProvider(_instanceId).future);
      expect(repository.callCount, 1);

      subscription.close();
      // Let autoDispose's scheduled teardown run — Riverpod defers
      // disposal (a short grace period, so a provider briefly losing its
      // last listener during a rebuild isn't torn down prematurely), so a
      // bare synchronous check isn't enough here.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      container.listen(serverListControllerProvider(_instanceId), (_, _) {});
      await container.read(serverListControllerProvider(_instanceId).future);

      expect(
        repository.callCount,
        2,
        reason: 'a second build() call proves the previous state was disposed, not reused, once unwatched',
      );
    });
  });

  group('ServerListController — disposal during an in-flight operation', () {
    test('refresh() does not throw when the container is disposed while it is in flight', () async {
      final repository = _ControlledServerRepository();
      final container = ProviderContainer(
        retry: noAutomaticProviderRetry,
        overrides: [serverRepositoryProvider(_instanceId).overrideWithValue(repository)],
      );
      container.listen(serverListControllerProvider(_instanceId), (_, _) {});

      repository.gate.complete(const ServerPage(servers: [], page: 1, totalPages: 1));
      await container.read(serverListControllerProvider(_instanceId).future);

      repository.gate = Completer<ServerPage>(); // block the next call (refresh)
      final refreshFuture = container.read(serverListControllerProvider(_instanceId).notifier).refresh();
      await Future<void>.delayed(Duration.zero); // let refresh() reach the blocked repository call

      container.dispose(); // simulate leaving the screen mid-refresh

      repository.gate.complete(const ServerPage(servers: [], page: 1, totalPages: 1));

      await expectLater(refreshFuture, completes);
    });
  });
}
