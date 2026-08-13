import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pterodactyl_mobile/app/app_provider_policy.dart';
import 'package:pterodactyl_mobile/core/theme/app_theme.dart';
import 'package:pterodactyl_mobile/features/instances/presentation/screens/add_instance_screen.dart';

// Keys mirror the ones `AddInstanceScreen` assigns its fields — using
// `find.byKey` instead of `find.byType` because `PageView` (built with an
// explicit `children:` list, not `.builder`) keeps adjacent wizard steps
// in the widget tree even off-screen, so more than one `TextField` can be
// findable at once.
const _urlField = Key('addPanel.urlField');
const _apiKeyField = Key('addPanel.apiKeyField');

Widget _wrap() {
  return ProviderScope(
    retry: noAutomaticProviderRetry,
    child: MaterialApp(theme: AppTheme.light(), home: const AddInstanceScreen()),
  );
}

void main() {
  group('AddInstanceScreen wizard', () {
    testWidgets('step 1 requires a valid URL before advancing', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      expect(find.text('Adres panelu'), findsOneWidget);

      // Empty URL: tapping "Dalej" must not advance.
      await tester.tap(find.text('Dalej'));
      await tester.pumpAndSettle();
      expect(find.text('Adres panelu'), findsOneWidget);

      await tester.enterText(find.byKey(_urlField), 'https://panel.example.com');
      await tester.tap(find.text('Dalej'));
      await tester.pumpAndSettle();

      expect(find.text('Klucz API'), findsOneWidget);
    });

    testWidgets('step 2 "Dalej" stays disabled until the key looks plausible', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(_urlField), 'https://panel.example.com');
      await tester.tap(find.text('Dalej'));
      await tester.pumpAndSettle();

      Finder nextButton() => find.widgetWithText(FilledButton, 'Dalej');
      expect(tester.widget<FilledButton>(nextButton()).onPressed, isNull);

      await tester.enterText(find.byKey(_apiKeyField), 'ptlc_1234567890');
      await tester.pump();
      expect(tester.widget<FilledButton>(nextButton()).onPressed, isNotNull);

      await tester.tap(nextButton());
      await tester.pumpAndSettle();

      expect(find.text('Nazwa i test połączenia'), findsOneWidget);
    });

    testWidgets('step 3 starts with the connection test idle and "Zapisz i zakończ" disabled', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(_urlField), 'https://panel.example.com');
      await tester.tap(find.text('Dalej'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(_apiKeyField), 'ptlc_1234567890');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Dalej'));
      await tester.pumpAndSettle();

      expect(find.text('Gotowe do testu'), findsOneWidget);
      expect(find.text('Testuj połączenie'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Zapisz i zakończ')).onPressed, isNull);
    });
  });
}
