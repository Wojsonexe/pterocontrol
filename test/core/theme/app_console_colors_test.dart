import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pterodactyl_mobile/core/theme/app_console_colors.dart';
import 'package:pterodactyl_mobile/core/theme/app_theme.dart';

void main() {
  group('AppConsoleColors', () {
    test('matches the literal values ConsoleView historically hard-coded', () {
      expect(AppConsoleColors.value.background, const Color(0xFF0D1117));
      expect(AppConsoleColors.value.mutedText, const Color(0xFF8B949E));
      expect(AppConsoleColors.value.outputText, const Color(0xFFC9D1D9));
      expect(AppConsoleColors.value.daemonMessageText, const Color(0xFF58A6FF));
      expect(AppConsoleColors.value.daemonErrorText, const Color(0xFFFF7B72));
    });

    testWidgets('is registered identically in both AppTheme.light() and AppTheme.dark()', (tester) async {
      late AppConsoleColors light;
      late AppConsoleColors dark;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) {
              light = AppConsoleColors.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Builder(
            builder: (context) {
              dark = AppConsoleColors.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(light.background, dark.background);
      expect(light.outputText, dark.outputText);
    });
  });
}
