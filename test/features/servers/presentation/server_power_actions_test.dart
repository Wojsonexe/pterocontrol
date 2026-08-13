import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pterodactyl_mobile/app/app_provider_policy.dart';
import 'package:pterodactyl_mobile/core/error/app_exception.dart';
import 'package:pterodactyl_mobile/core/theme/app_theme.dart';
import 'package:pterodactyl_mobile/features/servers/application/servers_providers.dart';
import 'package:pterodactyl_mobile/features/servers/domain/server.dart';
import 'package:pterodactyl_mobile/features/servers/domain/server_page.dart';
import 'package:pterodactyl_mobile/features/servers/domain/server_power_action.dart';
import 'package:pterodactyl_mobile/features/servers/domain/server_repository.dart';
import 'package:pterodactyl_mobile/features/servers/domain/server_runtime_state.dart';
import 'package:pterodactyl_mobile/features/servers/presentation/widgets/server_power_actions.dart';

const _instanceId = 'instance-a';

Server _server({ServerAdministrativeStatus status = ServerAdministrativeStatus.active}) => Server(
      identifier: 'srv-1',
      uuid: 'uuid-srv-1',
      name: 'Survival SMP',
      node: 'Node 1',
      status: status,
      isTransferring: false,
      limits: const ServerLimits(memoryMb: 1024, diskMb: 4096, cpuPercent: 100),
    );

class _FakeServerRepository implements ServerRepository {
  _FakeServerRepository({this.error});

  AppException? error;
  int powerActionCallCount = 0;
  ServerPowerAction? lastAction;

  @override
  Future<ServerPage> getServers({int page = 1}) async => ServerPage(servers: [_server()], page: 1, totalPages: 1);

  @override
  Future<void> sendPowerAction(String serverIdentifier, ServerPowerAction action) async {
    powerActionCallCount++;
    lastAction = action;
    if (error != null) throw error!;
  }

  @override
  Future<Server> getServer(String serverIdentifier) async => _server();

  @override
  Future<ServerRuntimeState> getResourceUsage(String serverIdentifier) async => ServerRuntimeState.unknown;
}

Widget _wrap(ServerRepository repository, {ServerAdministrativeStatus status = ServerAdministrativeStatus.active}) {
  return ProviderScope(
    retry: noAutomaticProviderRetry,
    overrides: [serverRepositoryProvider(_instanceId).overrideWithValue(repository)],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: ServerPowerActions(instanceId: _instanceId, server: _server(status: status))),
    ),
  );
}

/// Finds the button (`FilledButton`/`OutlinedButton`/...) containing [text].
///
/// Deliberately not `find.widgetWithText(FilledButton, text)`: Flutter's
/// `FilledButton.icon(...)` factory returns a private `_FilledButtonWithIcon`
/// subclass, and `find.byType` matches by exact runtime type — it would
/// never find it. Matching on the shared `ButtonStyleButton` base via a
/// predicate (an `is` check) works for every Material button variant
/// regardless of which concrete class an `.icon` factory happens to return.
Finder _buttonWithText(String text) {
  return find.ancestor(
    of: find.text(text),
    matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
  );
}

void main() {
  group('ServerPowerActions', () {
    testWidgets('tapping Start sends the start signal and shows a success SnackBar', (tester) async {
      final repository = _FakeServerRepository();
      await tester.pumpWidget(_wrap(repository));
      await tester.pumpAndSettle();

      await tester.tap(_buttonWithText('Start'));
      await tester.pumpAndSettle();

      expect(repository.powerActionCallCount, 1);
      expect(repository.lastAction, ServerPowerAction.start);
      expect(find.text('Wysłano polecenie: Start'), findsOneWidget);
    });

    testWidgets('tapping Kill shows a confirmation dialog and sends nothing if cancelled', (tester) async {
      final repository = _FakeServerRepository();
      await tester.pumpWidget(_wrap(repository));
      await tester.pumpAndSettle();

      await tester.tap(_buttonWithText('Kill'));
      await tester.pumpAndSettle();

      expect(find.text('Wymusić zatrzymanie serwera?'), findsOneWidget);

      await tester.tap(find.text('Anuluj'));
      await tester.pumpAndSettle();

      expect(repository.powerActionCallCount, 0);
    });

    testWidgets('tapping Kill and confirming sends the kill signal', (tester) async {
      final repository = _FakeServerRepository();
      await tester.pumpWidget(_wrap(repository));
      await tester.pumpAndSettle();

      await tester.tap(_buttonWithText('Kill'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wymuś Kill'));
      await tester.pumpAndSettle();

      expect(repository.powerActionCallCount, 1);
      expect(repository.lastAction, ServerPowerAction.kill);
    });

    testWidgets('shows an error SnackBar with the mapped message on failure', (tester) async {
      final repository = _FakeServerRepository(error: const ForbiddenException());
      await tester.pumpWidget(_wrap(repository));
      await tester.pumpAndSettle();

      await tester.tap(_buttonWithText('Stop'));
      await tester.pumpAndSettle();

      expect(find.text(const ForbiddenException().message), findsOneWidget);
    });

    testWidgets('disables every action button when the server is not active', (tester) async {
      final repository = _FakeServerRepository();
      await tester.pumpWidget(_wrap(repository, status: ServerAdministrativeStatus.suspended));
      await tester.pumpAndSettle();

      final startButton = tester.widget<ButtonStyleButton>(_buttonWithText('Start'));
      final restartButton = tester.widget<ButtonStyleButton>(_buttonWithText('Restart'));
      final stopButton = tester.widget<ButtonStyleButton>(_buttonWithText('Stop'));
      final killButton = tester.widget<ButtonStyleButton>(_buttonWithText('Kill'));

      expect(startButton.onPressed, isNull);
      expect(restartButton.onPressed, isNull);
      expect(stopButton.onPressed, isNull);
      expect(killButton.onPressed, isNull);
    });
  });
}
