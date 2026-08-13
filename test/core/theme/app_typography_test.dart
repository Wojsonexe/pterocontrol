import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pterodactyl_mobile/core/theme/app_typography.dart';

void main() {
  group('AppTypography.textTheme', () {
    final textTheme = AppTypography.textTheme(
      ColorScheme.fromSeed(seedColor: const Color(0xFF4A54F1)),
    );

    test('AppBar/section role (titleLarge) uses the display face, semibold', () {
      expect(textTheme.titleLarge?.fontSize, 18);
      expect(textTheme.titleLarge?.fontFamily, 'Sora');
      expect(textTheme.titleLarge?.fontWeight, FontWeight.w600);
    });

    test('Title element role (titleMedium) uses the text face, semibold', () {
      expect(textTheme.titleMedium?.fontSize, 15);
      expect(textTheme.titleMedium?.fontFamily, 'Inter');
      expect(textTheme.titleMedium?.fontWeight, FontWeight.w600);
    });

    test('Body główna role (bodyLarge)', () {
      expect(textTheme.bodyLarge?.fontSize, 16);
      expect(textTheme.bodyLarge?.fontFamily, 'Inter');
      expect(textTheme.bodyLarge?.fontWeight, FontWeight.w400);
    });

    test('Body drugorzędna / Caption role (bodyMedium/bodySmall)', () {
      expect(textTheme.bodyMedium?.fontSize, 14);
      expect(textTheme.bodySmall?.fontSize, 12.5);
    });

    test('Label/button role (labelLarge) is semibold', () {
      expect(textTheme.labelLarge?.fontSize, 14);
      expect(textTheme.labelLarge?.fontWeight, FontWeight.w600);
    });

    test('Label/status badge role (labelMedium) is semibold', () {
      expect(textTheme.labelMedium?.fontSize, 12);
      expect(textTheme.labelMedium?.fontWeight, FontWeight.w600);
    });

    test('Screen hero title role (headlineSmall) uses the display face', () {
      expect(textTheme.headlineSmall?.fontSize, 20);
      expect(textTheme.headlineSmall?.fontFamily, 'Sora');
    });

    test('Display role (displaySmall) — reserved, unused today', () {
      expect(textTheme.displaySmall?.fontSize, 28);
    });

    test('display/headline/titleLarge roles use the Sora display face', () {
      final displayRoles = [
        textTheme.displayLarge,
        textTheme.displayMedium,
        textTheme.displaySmall,
        textTheme.headlineLarge,
        textTheme.headlineMedium,
        textTheme.headlineSmall,
        textTheme.titleLarge,
      ];
      for (final style in displayRoles) {
        expect(style?.fontFamily, 'Sora');
      }
    });

    test('body/label/titleMedium/titleSmall roles use the Inter text face', () {
      final textRoles = [
        textTheme.titleMedium,
        textTheme.titleSmall,
        textTheme.bodyLarge,
        textTheme.bodyMedium,
        textTheme.bodySmall,
        textTheme.labelLarge,
        textTheme.labelMedium,
        textTheme.labelSmall,
      ];
      for (final style in textRoles) {
        expect(style?.fontFamily, 'Inter');
      }
    });

    test('only w400/w600 weights are used across the whole scale', () {
      final weights = [
        textTheme.displayLarge,
        textTheme.displayMedium,
        textTheme.displaySmall,
        textTheme.headlineLarge,
        textTheme.headlineMedium,
        textTheme.headlineSmall,
        textTheme.titleLarge,
        textTheme.titleMedium,
        textTheme.titleSmall,
        textTheme.bodyLarge,
        textTheme.bodyMedium,
        textTheme.bodySmall,
        textTheme.labelLarge,
        textTheme.labelMedium,
        textTheme.labelSmall,
      ].map((style) => style?.fontWeight).whereType<FontWeight>();

      for (final weight in weights) {
        expect(
          weight == FontWeight.w400 || weight == FontWeight.w600,
          isTrue,
          reason: 'unexpected weight $weight — design system allows only w400/w600 in TextTheme',
        );
      }
    });

    test('text colors are resolved from the ColorScheme, not left null', () {
      expect(textTheme.bodyLarge?.color, isNotNull);
      expect(textTheme.titleMedium?.color, isNotNull);
    });
  });

  group('AppTypography.metricNumber', () {
    test('uses the display face with tabular figures', () {
      expect(AppTypography.metricNumber.fontFamily, 'Sora');
      expect(AppTypography.metricNumber.fontFeatures, contains(const FontFeature.tabularFigures()));
    });
  });

  group('AppTypography.terminal', () {
    test("stays monospace, matching ConsoleView's existing style", () {
      expect(AppTypography.terminal.fontFamily, 'monospace');
      expect(AppTypography.terminal.fontSize, 13);
    });
  });
}
