import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pterodactyl_mobile/app/app.dart';
import 'package:pterodactyl_mobile/app/app_provider_policy.dart';
import 'package:pterodactyl_mobile/core/presentation/widgets/app_bottom_nav.dart';
import 'package:pterodactyl_mobile/core/storage/shared_preferences_provider.dart';
import 'package:pterodactyl_mobile/features/instances/application/instance_providers.dart';
import 'package:pterodactyl_mobile/features/instances/domain/instance_repository.dart';
import 'package:pterodactyl_mobile/features/instances/domain/pterodactyl_instance.dart';
import 'package:pterodactyl_mobile/features/servers/application/servers_providers.dart';
import 'package:pterodactyl_mobile/features/servers/domain/server_page.dart';
import 'package:pterodactyl_mobile/features/servers/domain/server_power_action.dart';
import 'package:pterodactyl_mobile/features/servers/domain/server_repository.dart';
import 'package:pterodactyl_mobile/features/servers/domain/server_runtime_state.dart';
import 'package:pterodactyl_mobile/features/servers/domain/server.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Empty, static [ServerRepository] — the third test below only needs the
/// shell to mount past `RootScreen`'s redirect; what Dashboard shows once
/// there is covered elsewhere (`dashboard_screen_test.dart`).
class _EmptyServerRepository implements ServerRepository {
  @override
  Future<ServerPage> getServers({int page = 1}) async => const ServerPage(servers: [], page: 1, totalPages: 1);

  @override
  Future<void> sendPowerAction(String serverIdentifier, ServerPowerAction action) async {
    throw UnimplementedError('not exercised by this test');
  }

  @override
  Future<Server> getServer(String serverIdentifier) async => throw UnimplementedError('not exercised by this test');

  @override
  Future<ServerRuntimeState> getResourceUsage(String serverIdentifier) async => ServerRuntimeState.unknown;
}

/// [InstanceRepository] whose starting contents are fixed at construction
/// — lets each test express exactly one of the three states [RootScreen]
/// branches on, without depending on `SharedPreferences`/wizard flows.
class _FakeInstanceRepository implements InstanceRepository {
  _FakeInstanceRepository({List<PterodactylInstance> instances = const [], String? activeInstanceId})
      : _instances = {for (final i in instances) i.id: i},
        _activeId = activeInstanceId;

  final Map<String, PterodactylInstance> _instances;
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

Future<void> _pumpApp(WidgetTester tester, InstanceRepository repository) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      retry: noAutomaticProviderRetry,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        instanceRepositoryProvider.overrideWithValue(repository),
      ],
      child: const PterodactylMobileApp(),
    ),
  );
}

void main() {
  group('RootScreen entry flow', () {
    testWidgets('no panel ever configured -> WelcomeScreen, not the picker', (tester) async {
      await _pumpApp(tester, _FakeInstanceRepository());
      await tester.pumpAndSettle();

      expect(find.text('Połącz panel'), findsOneWidget);
      expect(find.text('Panele'), findsNothing, reason: 'the picker AppBar must not appear for a brand-new device');
    });

    testWidgets('panels exist but none is active -> the picker, not the welcome screen', (tester) async {
      final repository = _FakeInstanceRepository(
        instances: const [PterodactylInstance(id: 'a', name: 'Home server', baseUrl: 'https://panel.example.com')],
      );
      await _pumpApp(tester, repository);
      await tester.pumpAndSettle();

      expect(find.text('Panele'), findsOneWidget);
      expect(find.text('Home server'), findsOneWidget);
      expect(find.text('Połącz panel'), findsNothing, reason: 'a returning user with saved panels must not see onboarding copy again');
    });

    testWidgets('an active instance redirects straight past both welcome and picker', (tester) async {
      final repository = _FakeInstanceRepository(
        instances: const [PterodactylInstance(id: 'a', name: 'Home server', baseUrl: 'https://panel.example.com')],
        activeInstanceId: 'a',
      );
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          retry: noAutomaticProviderRetry,
          overrides: [
            sharedPreferencesProvider.overrideWithValue(preferences),
            instanceRepositoryProvider.overrideWithValue(repository),
            serverRepositoryProvider('a').overrideWithValue(_EmptyServerRepository()),
          ],
          child: const PterodactylMobileApp(),
        ),
      );
      // Safe to `pumpAndSettle` here (unlike the Dashboard-with-real-servers
      // tests elsewhere in this suite): zero servers means
      // `ServerRuntimeSyncController`'s tick finds nothing to sync and
      // never reaches `ServerSyncStatus.live`, so `SyncStatusIndicator`'s
      // perpetually-pulsing dot never starts and can't stop this from
      // settling.
      await tester.pumpAndSettle();

      expect(find.text('Połącz panel'), findsNothing);
      expect(find.text('Panele'), findsNothing);
      expect(find.byType(AppBottomNav), findsOneWidget, reason: 'landed straight on the main shell');
    });
  });
}
