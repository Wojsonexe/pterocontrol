import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pterodactyl_mobile/core/theme/app_console_colors.dart';
import 'package:pterodactyl_mobile/core/theme/app_radius.dart';
import 'package:pterodactyl_mobile/core/theme/app_semantic_colors.dart';
import 'package:pterodactyl_mobile/core/theme/app_theme.dart';

void main() {
  group('AppTheme.light', () {
    final theme = AppTheme.light();

    test('builds without throwing and uses Material 3', () {
      expect(theme.useMaterial3, isTrue);
      expect(theme.colorScheme.brightness, Brightness.light);
    });

    test('registers AppSemanticColors and AppConsoleColors as extensions', () {
      expect(theme.extension<AppSemanticColors>(), AppSemanticColors.light);
      expect(theme.extension<AppConsoleColors>(), AppConsoleColors.value);
    });

    test('card theme uses AppRadius.md and an outlined, flat style', () {
      final shape = theme.cardTheme.shape as RoundedRectangleBorder?;
      expect(shape?.borderRadius, BorderRadius.circular(AppRadius.md));
      expect(theme.cardTheme.elevation, 0);
    });

    test('button themes are configured', () {
      expect(theme.filledButtonTheme.style, isNotNull);
      expect(theme.outlinedButtonTheme.style, isNotNull);
      expect(theme.textButtonTheme.style, isNotNull);
      expect(theme.iconButtonTheme.style, isNotNull);
    });

    test('input decoration theme uses AppRadius.sm and defines all interaction states', () {
      expect(theme.inputDecorationTheme.focusedBorder, isNotNull);
      expect(theme.inputDecorationTheme.errorBorder, isNotNull);
      expect(theme.inputDecorationTheme.focusedErrorBorder, isNotNull);
      expect(theme.inputDecorationTheme.disabledBorder, isNotNull);
    });
  });

  group('AppTheme.dark', () {
    final theme = AppTheme.dark();

    test('builds without throwing and uses Material 3', () {
      expect(theme.useMaterial3, isTrue);
      expect(theme.colorScheme.brightness, Brightness.dark);
    });

    test('registers the dark AppSemanticColors preset', () {
      expect(theme.extension<AppSemanticColors>(), AppSemanticColors.dark);
    });

    test('registers the same AppConsoleColors as light (console is theme-invariant)', () {
      expect(theme.extension<AppConsoleColors>(), AppConsoleColors.value);
    });
  });

  group('AppTheme — light vs dark', () {
    test('produce different-brightness ColorSchemes from the same seed', () {
      final light = AppTheme.light();
      final dark = AppTheme.dark();
      expect(light.colorScheme.brightness, isNot(dark.colorScheme.brightness));
    });
  });
}
