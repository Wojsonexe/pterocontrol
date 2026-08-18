import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pterodactyl_mobile/app/app_provider_policy.dart';
import 'package:pterodactyl_mobile/core/theme/app_theme.dart';
import 'package:pterodactyl_mobile/features/console/application/console_providers.dart';
import 'package:pterodactyl_mobile/features/console/domain/console_connection_state.dart';
import 'package:pterodactyl_mobile/features/console/domain/console_event.dart';
import 'package:pterodactyl_mobile/features/console/presentation/widgets/console_view.dart';

import '../../../../support/fake_console_repository.dart';

const _instanceId = 'instance-a';
const _serverIdentifier = 'srv-1';

Future<void> _pump(WidgetTester tester, FakeConsoleRepository repository) async {
  await tester.pumpWidget(
    ProviderScope(
      retry: noAutomaticProviderRetry,
      overrides: [
        consoleRepositoryProvider((instanceId: _instanceId, serverIdentifier: _serverIdentifier))
            .overrideWithValue(repository),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: ConsoleView(instanceId: _instanceId, serverIdentifier: _serverIdentifier)),
      ),
    ),
  );
}

List<ConsoleEvent> _lines(int count, {int startAt = 1}) {
  return [
    for (var i = startAt; i < startAt + count; i++)
      ConsoleEvent(type: ConsoleEventType.output, message: 'line $i', timestamp: DateTime.now()),
  ];
}

void main() {
  group('ConsoleView — connection status', () {
    testWidgets('shows "Łączenie…" while connecting', (tester) async {
      final repository = FakeConsoleRepository();
      await _pump(tester, repository);
      repository.emitConnectionState(ConsoleConnectionState.connecting);
      await tester.pump();

      expect(find.text('Łączenie…'), findsOneWidget);
    });

    testWidgets('shows "Uwierzytelnianie…" while authenticating', (tester) async {
      final repository = FakeConsoleRepository();
      await _pump(tester, repository);
      repository.emitConnectionState(ConsoleConnectionState.authenticating);
      await tester.pump();

      expect(find.text('Uwierzytelnianie…'), findsOneWidget);
    });

    testWidgets('shows "Połączono" once connected', (tester) async {
      final repository = FakeConsoleRepository();
      await _pump(tester, repository);
      repository.emitConnectionState(ConsoleConnectionState.connected);
      await tester.pump();

      expect(find.text('Połączono'), findsOneWidget);
    });

    testWidgets('shows an error indicator and a manual reconnect button on error', (tester) async {
      final repository = FakeConsoleRepository();
      await _pump(tester, repository);
      repository.emitConnectionState(ConsoleConnectionState.error);
      await tester.pump();

      expect(find.text('Błąd połączenia'), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });
  });

  group('ConsoleView — empty/loading states', () {
    testWidgets('shows an empty-state message when connected with no output yet', (tester) async {
      final repository = FakeConsoleRepository();
      await _pump(tester, repository);
      repository.emitConnectionState(ConsoleConnectionState.connected);
      repository.emitEvents(const []);
      await tester.pump();

      expect(find.text('Brak danych z konsoli.'), findsOneWidget);
    });
  });

  group('ConsoleView — auto-scroll', () {
    testWidgets('auto-scrolls to the bottom when new output arrives while already at the bottom', (tester) async {
      final repository = FakeConsoleRepository();
      await _pump(tester, repository);
      repository.emitConnectionState(ConsoleConnectionState.connected);

      repository.emitEvents(_lines(60));
      await tester.pump();
      await tester.pump();

      final controller = tester.widget<ListView>(find.byType(ListView)).controller!;
      expect(controller.position.pixels, controller.position.maxScrollExtent);

      repository.emitEvents([..._lines(60), ..._lines(10, startAt: 61)]);
      await tester.pump();
      await tester.pump();

      expect(
        controller.position.pixels,
        controller.position.maxScrollExtent,
        reason: 'still at the bottom, so new output must keep it pinned to the bottom',
      );
    });

    testWidgets('does not force-scroll when the user has scrolled up to read scrollback', (tester) async {
      final repository = FakeConsoleRepository();
      await _pump(tester, repository);
      repository.emitConnectionState(ConsoleConnectionState.connected);

      repository.emitEvents(_lines(60));
      await tester.pump();
      await tester.pump();

      final controller = tester.widget<ListView>(find.byType(ListView)).controller!;
      // Scroll up, away from the bottom, to read earlier output.
      controller.jumpTo(0);
      await tester.pump();
      expect(controller.position.pixels, 0);

      // More output arrives while the user is still reading scrollback.
      repository.emitEvents(_lines(70));
      await tester.pump();
      await tester.pump();

      expect(
        controller.position.pixels,
        0,
        reason: 'the view must not be yanked back to the bottom while the user is reading scrollback',
      );
    });
  });

  group('ConsoleView — command input', () {
    testWidgets('sending a command clears the field and calls the repository', (tester) async {
      final repository = FakeConsoleRepository();
      await _pump(tester, repository);
      repository.emitConnectionState(ConsoleConnectionState.connected);
      repository.emitEvents(const []);
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'say hello');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();

      expect(repository.sentCommands, ['say hello']);
      expect(find.text('say hello'), findsNothing);
    });

    testWidgets('the command field is disabled while not connected', (tester) async {
      final repository = FakeConsoleRepository();
      await _pump(tester, repository);
      repository.emitConnectionState(ConsoleConnectionState.connecting);
      await tester.pump();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.enabled, isFalse);
    });
  });
}
