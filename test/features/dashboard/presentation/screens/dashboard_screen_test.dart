import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pterodactyl_mobile/app/app_provider_policy.dart';
import 'package:pterodactyl_mobile/app/lifecycle/app_lifecycle_controller.dart';
import 'package:pterodactyl_mobile/core/error/app_exception.dart';
import 'package:pterodactyl_mobile/core/theme/app_theme.dart';
import 'package:pterodactyl_mobile/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:pterodactyl_mobile/features/instances/application/instance_providers.dart';
import 'package:pterodactyl_mobile/features/instances/domain/instance_repository.dart';
import 'package:pterodactyl_mobile/features/instances/domain/pterodactyl_instance.dart';
import 'package:pterodactyl_mobile/features/servers/application/servers_providers.dart';
import 'package:pterodactyl_mobile/features/servers/domain/server.dart';
import 'package:pterodactyl_mobile/features/servers/domain/server_page.dart';
import 'package:pterodactyl_mobile/features/servers/domain/server_power_action.dart';
import 'package:pterodactyl_mobile/features/servers/domain/server_power_state.dart';
import 'package:pterodactyl_mobile/features/servers/domain/server_repository.dart';
import 'package:pterodactyl_mobile/features/servers/domain/server_runtime_state.dart';

const _instanceId = 'instance-a';
const _instance = PterodactylInstance(id: _instanceId, name: 'Home server', baseUrl: 'https://a.example.com');

class _FakeInstanceRepository implements InstanceRepository {
  final _instances = <String, PterodactylInstance>{_instanceId: _instance};
  String? _activeId = _instanceId;

  @override
  Future<List<PterodactylInstance>> getAll() async => _instances.values.toList();

  @override
  Future<void> add(PterodactylInstance instance) async => _instances[instance.id] = instance;

  @override
  Future<void> update(PterodactylInstance instance) async => _instances[instance.id] = instance;

  @override
  Future<void> remove(String instanceId) async => _instances.remove(instanceId);

  @override
  Future<String?> getActiveInstanceId() async => _activeId;

  @override
  Future<void> setActiveInstanceId(String? instanceId) async => _activeId = instanceId;
}

class _FakeServerRepository implements ServerRepository {
  _FakeServerRepository(this.page);

  final ServerPage page;

  @override
  Future<ServerPage> getServers({int page = 1}) async => this.page;

  @override
  Future<void> sendPowerAction(String serverIdentifier, ServerPowerAction action) async {
    throw UnimplementedError('not exercised by this test');
  }

  @override
  Future<Server> getServer(String serverIdentifier) async {
    return page.servers.firstWhere((s) => s.identifier == serverIdentifier);
  }

  @override
  Future<ServerRuntimeState> getResourceUsage(String serverIdentifier) async => ServerRuntimeState.unknown;
}

Server _server(
  String id,
  String name, {
  ServerAdministrativeStatus status = ServerAdministrativeStatus.active,
  int memoryMb = 1024,
  int diskMb = 2048,
}) =>
    Server(
      identifier: id,
      uuid: 'uuid-$id',
      name: name,
      node: 'Node 1',
      status: status,
      isTransferring: false,
      limits: ServerLimits(memoryMb: memoryMb, diskMb: diskMb, cpuPercent: 100),
    );

/// A repository whose [getServer]/[getResourceUsage] answers can be
/// changed *after* construction — for tests that need a second poll tick
/// to observe different data than the first (a live status/metric
/// transition), which a fixed fake cannot express.
class _MutableFakeServerRepository implements ServerRepository {
  _MutableFakeServerRepository(this.page);

  ServerPage page;
  Map<String, ServerRuntimeState> resourceUsageByIdentifier = const {};

  @override
  Future<ServerPage> getServers({int page = 1}) async => this.page;

  @override
  Future<void> sendPowerAction(String serverIdentifier, ServerPowerAction action) async {
    throw UnimplementedError('not exercised by this test');
  }

  @override
  Future<Server> getServer(String serverIdentifier) async {
    return page.servers.firstWhere((s) => s.identifier == serverIdentifier);
  }

  @override
  Future<ServerRuntimeState> getResourceUsage(String serverIdentifier) async {
    return resourceUsageByIdentifier[serverIdentifier] ?? ServerRuntimeState.unknown;
  }
}

/// A [ServerRepository] whose [getResourceUsage] never resolves until the
/// test explicitly completes [resourcesGate] — for proving the Dashboard
/// renders servers from `GET /api/client` without waiting on
/// `.../resources` at all.
class _GatedServerRepository implements ServerRepository {
  _GatedServerRepository(this.page);

  final ServerPage page;
  final resourcesGate = Completer<void>();

  @override
  Future<ServerPage> getServers({int page = 1}) async => this.page;

  @override
  Future<void> sendPowerAction(String serverIdentifier, ServerPowerAction action) async {
    throw UnimplementedError('not exercised by this test');
  }

  @override
  Future<Server> getServer(String serverIdentifier) async {
    return page.servers.firstWhere((s) => s.identifier == serverIdentifier);
  }

  @override
  Future<ServerRuntimeState> getResourceUsage(String serverIdentifier) async {
    await resourcesGate.future;
    return ServerRuntimeState.unknown;
  }
}

Widget _wrap(ServerRepository repository) {
  return ProviderScope(
    retry: noAutomaticProviderRetry,
    overrides: [
      instanceRepositoryProvider.overrideWithValue(_FakeInstanceRepository()),
      serverRepositoryProvider(_instanceId).overrideWithValue(repository),
    ],
    child: MaterialApp(theme: AppTheme.light(), home: const DashboardScreen()),
  );
}

void main() {
  group('DashboardScreen', () {
    testWidgets('shows the active instance name and a real server-status summary', (tester) async {
      final repository = _FakeServerRepository(
        ServerPage(
          servers: [
            _server('a', 'Survival'),
            _server('b', 'Creative'),
            _server('c', 'Lobby', status: ServerAdministrativeStatus.suspended),
          ],
          page: 1,
          totalPages: 1,
        ),
      );

      await tester.pumpWidget(_wrap(repository));
      // Not `pumpAndSettle`: two of these three servers are `active`, so
      // the immediate sync tick reaches `ServerSyncStatus.live` and
      // `SyncStatusIndicator`'s continuously pulsing dot starts — see the
      // identical fix (and full explanation) a few tests below in this
      // same file, at the "installing -> active" test.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));

      expect(find.text('Home server'), findsOneWidget);
      expect(find.text('3'), findsOneWidget, reason: 'total server count');
      expect(find.text('2'), findsOneWidget, reason: 'active count');
      expect(find.text('1'), findsOneWidget, reason: 'needs-attention count');
      expect(find.text('Survival'), findsOneWidget);
      expect(find.text('Creative'), findsOneWidget);
    });

    testWidgets('renders the server list before .../resources ever resolves', (tester) async {
      final repository = _GatedServerRepository(
        ServerPage(servers: [_server('a', 'Survival'), _server('b', 'Creative')], page: 1, totalPages: 1),
      );

      await tester.pumpWidget(_wrap(repository));
      // Two bare pumps, no elapsed duration: one lets `GET /api/client`
      // (a plain, un-gated `Future`) resolve, the second lets that
      // resolution's state write actually rebuild the widget tree.
      // `resourcesGate` is still open throughout, so every `.../resources`
      // call this screen made is still pending — nowhere near the real
      // 30s poll interval, so this stays clear of the `Timer.periodic` +
      // `pumpAndSettle` trap noted elsewhere in this file.
      await tester.pump();
      await tester.pump();

      expect(find.text('Survival'), findsOneWidget, reason: 'the list must render without waiting on resources');
      expect(find.text('Creative'), findsOneWidget);

      repository.resourcesGate.complete();
      await tester.pump();
    });

    testWidgets('shows an honest empty state when the instance has no servers', (tester) async {
      final repository = _FakeServerRepository(const ServerPage(servers: [], page: 1, totalPages: 1));

      await tester.pumpWidget(_wrap(repository));
      await tester.pumpAndSettle();

      expect(
        find.text('To konto nie ma jeszcze dostępu do żadnego serwera na tym panelu.'),
        findsOneWidget,
      );
    });

    testWidgets('shows an error view with retry on failure', (tester) async {
      final repository = _FailingServerRepository();

      await tester.pumpWidget(_wrap(repository));
      await tester.pumpAndSettle();

      expect(find.text('Serwer zwrócił nieoczekiwany błąd.'), findsOneWidget);
      expect(find.text('Spróbuj ponownie'), findsOneWidget);
    });

    testWidgets(
      'reflects a real backend status change (installing -> active) immediately, without leaving the screen',
      (tester) async {
        final repository = _MutableFakeServerRepository(
          ServerPage(
            servers: [_server('a', 'fivem', status: ServerAdministrativeStatus.installing)],
            page: 1,
            totalPages: 1,
          ),
        );

        // Not `pumpAndSettle`: `SyncStatusIndicator` shows a continuously
        // pulsing dot once sync status reaches `live` (see `StatusDot`),
        // which never "settles" — bounded pumps instead, the same fix
        // already applied elsewhere in this suite for indeterminate/
        // repeating animations (e.g. `server_detail_install_completed_test.dart`).
        await tester.pumpWidget(_wrap(repository));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 700));

        expect(find.text('Instalacja'), findsWidgets, reason: 'card badge for the installing server');
        expect(find.text('Aktywny'), findsNothing);

        // The install actually finishes on the backend — the next
        // `getServer()` call (already triggered automatically every poll
        // tick for transitional servers) would now report `active`.
        repository.page = ServerPage(
          servers: [_server('a', 'fivem', status: ServerAdministrativeStatus.active)],
          page: 1,
          totalPages: 1,
        );

        // Force a second `ServerRuntimeSyncController` poll tick the same
        // way the controller's own tests do — toggling app-lifecycle
        // visibility triggers an immediate tick without waiting on the
        // real 30s timer.
        final container = ProviderScope.containerOf(tester.element(find.byType(DashboardScreen)));
        container.read(appLifecycleControllerProvider.notifier).state = AppLifecycleState.paused;
        await tester.pump();
        container.read(appLifecycleControllerProvider.notifier).state = AppLifecycleState.resumed;
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 700));

        expect(find.text('Aktywny'), findsWidgets, reason: 'both the health card and the server card should update');
        expect(find.text('Instalacja'), findsNothing);
      },
    );

    testWidgets('has no layout overflow on a small phone screen with realistic live data', (tester) async {
      addTearDown(tester.view.reset);
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;

      final repository = _MutableFakeServerRepository(
        ServerPage(
          servers: [
            _server('a', 'A very long survival server name indeed', memoryMb: 16384, diskMb: 102400),
            _server('b', 'Creative', status: ServerAdministrativeStatus.suspended),
            _server('c', 'Lobby', status: ServerAdministrativeStatus.installing),
          ],
          page: 1,
          totalPages: 1,
        ),
      )..resourceUsageByIdentifier = {
          'a': ServerRuntimeState(
            powerState: ServerPowerState.running,
            observedAt: DateTime.now(),
            cpuAbsolutePercent: 987.6,
            memoryBytes: 15 * 1024 * 1024 * 1024,
            diskBytes: 90 * 1024 * 1024 * 1024,
            networkRxBytes: 500000,
            networkTxBytes: 250000,
            uptimeMs: 1000 * 60 * 60 * 24 * 12 + 1000 * 60 * 60 * 7,
          ),
        };

      await tester.pumpWidget(_wrap(repository));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));

      expect(tester.takeException(), isNull);
    });

    testWidgets('has no layout overflow on a large phone screen with realistic live data', (tester) async {
      addTearDown(tester.view.reset);
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1.0;

      final repository = _MutableFakeServerRepository(
        ServerPage(
          servers: [
            _server('a', 'Survival', memoryMb: 4096, diskMb: 20480),
            _server('b', 'Creative'),
          ],
          page: 1,
          totalPages: 1,
        ),
      )..resourceUsageByIdentifier = {
          'a': ServerRuntimeState(
            powerState: ServerPowerState.running,
            observedAt: DateTime.now(),
            cpuAbsolutePercent: 42,
            memoryBytes: 2 * 1024 * 1024 * 1024,
            diskBytes: 8 * 1024 * 1024 * 1024,
            networkRxBytes: 1200,
            networkTxBytes: 800,
            uptimeMs: 1000 * 60 * 95,
          ),
        };

      await tester.pumpWidget(_wrap(repository));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));

      expect(tester.takeException(), isNull);
    });
  });
}

class _FailingServerRepository implements ServerRepository {
  @override
  Future<ServerPage> getServers({int page = 1}) async => throw const ServerException();

  @override
  Future<void> sendPowerAction(String serverIdentifier, ServerPowerAction action) async {
    throw UnimplementedError('not exercised by this test');
  }

  @override
  Future<Server> getServer(String serverIdentifier) async => throw const ServerException();

  @override
  Future<ServerRuntimeState> getResourceUsage(String serverIdentifier) async => throw const ServerException();
}
