import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pterodactyl_mobile/core/presentation/widgets/app_status_badge.dart';
import 'package:pterodactyl_mobile/core/theme/app_status_tokens.dart';
import 'package:pterodactyl_mobile/core/theme/app_theme.dart';

Widget _wrap(Widget child) => MaterialApp(theme: AppTheme.light(), home: Scaffold(body: Center(child: child)));

void main() {
  group('AppStatusBadge', () {
    testWidgets('renders the label text', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const AppStatusBadge(
            visual: AppStatusVisual(icon: Icons.check_circle, label: 'Online', tone: AppStatusTone.success),
          ),
        ),
      );

      expect(find.text('Online'), findsOneWidget);
    });

    testWidgets('shows a static icon when isAnimated is false', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const AppStatusBadge(
            visual: AppStatusVisual(icon: Icons.check_circle, label: 'Online', tone: AppStatusTone.success),
          ),
        ),
      );

      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('shows a spinner instead of the icon when isAnimated is true', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const AppStatusBadge(
            visual: AppStatusVisual(
              icon: Icons.sync,
              label: 'Łączenie…',
              tone: AppStatusTone.pending,
              isAnimated: true,
            ),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('merges into a single Semantics node carrying the label', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const AppStatusBadge(
            visual: AppStatusVisual(icon: Icons.error, label: 'Błąd połączenia', tone: AppStatusTone.danger),
          ),
        ),
      );

      expect(find.bySemanticsLabel('Błąd połączenia'), findsOneWidget);
    });

    testWidgets('dense mode still renders label and icon', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const AppStatusBadge(
            visual: AppStatusVisual(icon: Icons.help_outline, label: 'Nieznany', tone: AppStatusTone.neutral),
            dense: true,
          ),
        ),
      );

      expect(find.text('Nieznany'), findsOneWidget);
      expect(find.byIcon(Icons.help_outline), findsOneWidget);
    });
  });
}
