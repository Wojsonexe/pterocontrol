import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pterodactyl_mobile/app/app_provider_policy.dart';
import 'package:pterodactyl_mobile/core/error/app_exception.dart';
import 'package:pterodactyl_mobile/core/theme/app_theme.dart';
import 'package:pterodactyl_mobile/features/instances/application/instance_providers.dart';
import 'package:pterodactyl_mobile/features/instances/domain/instance_repository.dart';
import 'package:pterodactyl_mobile/features/instances/domain/pterodactyl_instance.dart';
import 'package:pterodactyl_mobile/features/servers/application/servers_providers.dart';
import 'package:pterodactyl_mobile/features/servers/domain/server.dart';
import 'package:pterodactyl_mobile/features/servers/domain/server_page.dart';
import 'package:pterodactyl_mobile/features/servers/domain/server_power_action.dart';
import 'package:pterodactyl_mobile/features/servers/domain/server_repository.dart';
import 'package:pterodactyl_mobile/features/servers/domain/server_runtime_state.dart';
import 'package:pterodactyl_mobile/features/servers/presentation/screens/servers_screen.dart';

const _instanceId = 'instance-a';

class _FakeInstanceRepository implements InstanceRepository {
  final _instances = <String, PterodactylInstance>{
    _instanceId: const PterodactylInstance(id: _instanceId, name: 'Instance A', baseUrl: 'https://a.example.com'),
  };
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
  _FakeServerRepository({this.page, this.error});

  ServerPage? page;
  AppException? error;
  int callCount = 0;

  @override
  Future<ServerPage> getServers({int page = 1}) async {
    callCount++;
    if (error != null) throw error!;
    return this.page!;
  }

  @override
  Future<void> sendPowerAction(String serverIdentifier, ServerPowerAction action) async {
    throw UnimplementedError('not exercised by these tests');
  }

  @override
  Future<Server> getServer(String serverIdentifier) async {
    return page!.servers.firstWhere((s) => s.identifier == serverIdentifier);
  }

  @override
  Future<ServerRuntimeState> getResourceUsage(String serverIdentifier) async => ServerRuntimeState.unknown;
}

Server _server(String id, String name) => Server(
      identifier: id,
      uuid: 'uuid-$id',
      name: name,
      node: 'Node 1',
      status: ServerAdministrativeStatus.active,
      isTransferring: false,
      limits: const ServerLimits(memoryMb: 512, diskMb: 1024, cpuPercent: 100),
    );

Widget _wrap(ServerRepository repository) {
  return ProviderScope(
    retry: noAutomaticProviderRetry,
    overrides: [
      instanceRepositoryProvider.overrideWithValue(_FakeInstanceRepository()),
      serverRepositoryProvider(_instanceId).overrideWithValue(repository),
    ],
    child: MaterialApp(theme: AppTheme.light(), home: const ServersScreen()),
  );
}

void main() {
  group('ServersScreen', () {
    testWidgets('renders one tile per server', (tester) async {
      final repository = _FakeServerRepository(
        page: ServerPage(servers: [_server('a', 'Server A'), _server('b', 'Server B')], page: 1, totalPages: 1),
      );

      await tester.pumpWidget(_wrap(repository));
      // Not `pumpAndSettle`: both servers are `active`, so the immediate
      // sync tick reaches `ServerSyncStatus.live` and
      // `SyncStatusIndicator`'s continuously pulsing dot starts, which
      // never "settles" — same fix as `dashboard_screen_test.dart`.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));

      expect(find.text('Server A'), findsOneWidget);
      expect(find.text('Server B'), findsOneWidget);
    });

    testWidgets('shows the empty state when the instance has no servers', (tester) async {
      final repository = _FakeServerRepository(page: const ServerPage(servers: [], page: 1, totalPages: 1));

      await tester.pumpWidget(_wrap(repository));
      await tester.pumpAndSettle();

      expect(find.text('Brak serwerów'), findsOneWidget);
    });

    testWidgets('shows an error view with a retry action that re-fetches', (tester) async {
      final repository = _FakeServerRepository(error: const ServerException());

      await tester.pumpWidget(_wrap(repository));
      await tester.pumpAndSettle();

      expect(find.text('Serwer zwrócił nieoczekiwany błąd.'), findsOneWidget);
      expect(repository.callCount, 1);

      await tester.tap(find.text('Spróbuj ponownie'));
      await tester.pumpAndSettle();

      expect(repository.callCount, 2);
    });

    testWidgets('search filters the list client-side by name', (tester) async {
      final repository = _FakeServerRepository(
        page: ServerPage(servers: [_server('a', 'Survival'), _server('b', 'Creative')], page: 1, totalPages: 1),
      );

      await tester.pumpWidget(_wrap(repository));
      // Not `pumpAndSettle`: both servers are `active` — see "renders one
      // tile per server" above for why the sync status dot's animation
      // requires bounded pumps here.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));

      await tester.enterText(find.byType(TextField), 'surv');
      await tester.pump();

      expect(find.text('Survival'), findsOneWidget);
      expect(find.text('Creative'), findsNothing);
    });
  });
}
