import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pterodactyl_mobile/app/app.dart';
import 'package:pterodactyl_mobile/app/app_provider_policy.dart';
import 'package:pterodactyl_mobile/core/presentation/widgets/app_bottom_nav.dart';
import 'package:pterodactyl_mobile/core/presentation/widgets/app_top_bar.dart';
import 'package:pterodactyl_mobile/core/storage/shared_preferences_provider.dart';
import 'package:pterodactyl_mobile/features/console/application/console_providers.dart';
import 'package:pterodactyl_mobile/features/console/domain/console_connection_state.dart';
import 'package:pterodactyl_mobile/features/console/domain/console_event.dart';
import 'package:pterodactyl_mobile/features/console/domain/console_repository.dart';
import 'package:pterodactyl_mobile/features/instances/application/instance_providers.dart';
import 'package:pterodactyl_mobile/features/instances/domain/instance_repository.dart';
import 'package:pterodactyl_mobile/features/instances/domain/pterodactyl_instance.dart';
import 'package:pterodactyl_mobile/features/servers/application/servers_providers.dart';
import 'package:pterodactyl_mobile/features/servers/domain/server.dart';
import 'package:pterodactyl_mobile/features/servers/domain/server_page.dart';
import 'package:pterodactyl_mobile/features/servers/domain/server_power_action.dart';
import 'package:pterodactyl_mobile/features/servers/domain/server_repository.dart';
import 'package:pterodactyl_mobile/features/servers/domain/server_runtime_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeInstanceRepository implements InstanceRepository {
  final Map<String, PterodactylInstance> _instances = {};
  String? _activeId;

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
    throw UnimplementedError('not exercised by this navigation test');
  }

  @override
  Future<Server> getServer(String serverIdentifier) async {
    return page.servers.firstWhere((s) => s.identifier == serverIdentifier);
  }

  @override
  Future<ServerRuntimeState> getResourceUsage(String serverIdentifier) async => ServerRuntimeState.unknown;
}

/// Inert [ConsoleRepository]: this test is about screen/routing wiring,
/// not the console connection itself (that is covered in isolation by
/// `console_repository_impl_test.dart`). Overriding
/// `consoleRepositoryProvider` with this keeps `ServerDetailScreen` ->
/// `ConsoleView` from making a real HTTP/WebSocket connection attempt
/// (and leaving a reconnect `Timer` pending after the test body returns)
/// when it appears in the widget tree below.
class _NoopConsoleRepository implements ConsoleRepository {
  @override
  Stream<ConsoleConnectionState> get connectionState => const Stream.empty();

  @override
  Stream<ServerRuntimeState> get runtimeState => const Stream.empty();

  @override
  Stream<List<ConsoleEvent>> get events => const Stream.empty();

  @override
  Future<void> connect() async {}

  @override
  Future<void> disconnect() async {}

  @override
  void sendCommand(String command) {}

  @override
  Future<void> dispose() async {}
}

/// End-to-end-ish navigation test for the main `/app` shell: a returning
/// user (an instance is already active) lands straight on the Dashboard,
/// can switch to the Servers tab via the bottom navigation, and drilling
/// into a server opens `ServerDetailScreen`'s tabs (Overview showing real
/// data, Console present). Network/repository layers are faked (see
/// `servers_api_test.dart`/`server_repository_impl_test.dart` for those
/// in isolation); this test is about the UI/routing wiring.
void main() {
  testWidgets(
    'a returning user lands on Dashboard, can reach the full server list, and open a server',
    (tester) async {
      const instance = PterodactylInstance(
        id: 'instance-1',
        name: 'Home server',
        baseUrl: 'https://panel.example.com',
      );
      final instanceRepository = _FakeInstanceRepository();
      await instanceRepository.add(instance);
      await instanceRepository.setActiveInstanceId(instance.id);

      const server = Server(
        identifier: 'srv-1',
        uuid: 'uuid-srv-1',
        name: 'Survival SMP',
        node: 'Node 1',
        status: ServerAdministrativeStatus.active,
        isTransferring: false,
        limits: ServerLimits(memoryMb: 2048, diskMb: 10240, cpuPercent: 200),
      );
      final serverRepository = _FakeServerRepository(
        const ServerPage(servers: [server], page: 1, totalPages: 1),
      );

      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          retry: noAutomaticProviderRetry,
          overrides: [
            sharedPreferencesProvider.overrideWithValue(preferences),
            instanceRepositoryProvider.overrideWithValue(instanceRepository),
            serverRepositoryProvider(instance.id).overrideWithValue(serverRepository),
            consoleRepositoryProvider((instanceId: instance.id, serverIdentifier: server.identifier))
                .overrideWithValue(_NoopConsoleRepository()),
          ],
          child: const PterodactylMobileApp(),
        ),
      );
      // Not `pumpAndSettle`: once the immediate sync tick lands (server
      // is `active`), `ServerSyncStatus` reaches `live` and
      // `SyncStatusIndicator` shows a continuously pulsing dot (see
      // `StatusDot`), which never "settles" — `ServerRuntimeSyncController`
      // also keeps a real 30s `Timer.periodic` alive for as long as the
      // Dashboard is mounted, and `pumpAndSettle` would otherwise chase
      // that timer's fake-clock-elapsed firings forever. Same fix already
      // applied in `dashboard_screen_test.dart` for the identical cause.
      // Several bounded pumps rather than one big one: `RootScreen`'s own
      // splash -> instance-list load -> redirect chain (also an
      // indeterminate, never-settling `CircularProgressIndicator` while
      // it waits) is a few sequential async hops, not a single one.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      // RootScreen redirects straight to the Dashboard — an active
      // instance already exists, so the panel picker is never shown.
      expect(find.text('Home server'), findsOneWidget);
      expect(find.text('Survival SMP'), findsOneWidget, reason: 'Dashboard previews the server list');

      // Bottom navigation: switch to the full "Serwery" tab. Scoped to
      // `AppBottomNav` specifically: `StatefulShellRoute.indexedStack`
      // keeps every branch's screen mounted (just offstage), so a bare
      // `find.text('Serwery')` would ambiguously also match the Servers
      // screen's own (offstage) `AppTopBar` title.
      await tester.tap(find.descendant(of: find.byType(AppBottomNav), matching: find.text('Serwery')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.widgetWithText(AppTopBar, 'Serwery'), findsOneWidget);
      expect(find.text('Survival SMP'), findsOneWidget);

      await tester.tap(find.text('Survival SMP'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));

      // ServerDetailScreen: tabs, and the Overview tab's real data.
      expect(find.widgetWithText(AppTopBar, 'Survival SMP'), findsOneWidget);
      expect(find.text('Podsumowanie'), findsOneWidget);
      expect(find.text('Konsola'), findsOneWidget);
      expect(find.text('Pliki'), findsOneWidget);
      expect(find.text('Backupy'), findsOneWidget);
      expect(find.text('Node 1'), findsWidgets, reason: 'shown both in the header subtitle and the info grid');
      expect(find.text('2048 MB'), findsOneWidget);
    },
  );
}
