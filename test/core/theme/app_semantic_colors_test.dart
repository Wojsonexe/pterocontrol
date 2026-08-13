import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pterodactyl_mobile/core/theme/app_semantic_colors.dart';
import 'package:pterodactyl_mobile/core/theme/app_theme.dart';

void main() {
  group('AppSemanticColors presets', () {
    test('light and dark presets are distinct', () {
      expect(AppSemanticColors.light.success, isNot(AppSemanticColors.dark.success));
      expect(AppSemanticColors.light.danger, isNot(AppSemanticColors.dark.danger));
    });

    test("every role's \"on\" color is distinct from its own base color", () {
      for (final preset in [AppSemanticColors.light, AppSemanticColors.dark]) {
        expect(preset.onSuccess, isNot(preset.success));
        expect(preset.onPending, isNot(preset.pending));
        expect(preset.onDanger, isNot(preset.danger));
        expect(preset.onNeutral, isNot(preset.neutral));
      }
    });
  });

  group('AppSemanticColors.lerp/copyWith', () {
    test('lerp at t=0 returns this unchanged', () {
      final result = AppSemanticColors.light.lerp(AppSemanticColors.dark, 0);
      expect(result.success, AppSemanticColors.light.success);
    });

    test("lerp at t=1 returns the other extension's values", () {
      final result = AppSemanticColors.light.lerp(AppSemanticColors.dark, 1);
      expect(result.success, AppSemanticColors.dark.success);
    });

    test('copyWith overrides only the given field', () {
      const override = Color(0xFF123456);
      final result = AppSemanticColors.light.copyWith(success: override);
      expect(result.success, override);
      expect(result.danger, AppSemanticColors.light.danger);
    });
  });

  group('AppSemanticColors.of', () {
    testWidgets('resolves the extension registered by AppTheme.light()', (tester) async {
      late AppSemanticColors resolved;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) {
              resolved = AppSemanticColors.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(resolved.success, AppSemanticColors.light.success);
    });

    testWidgets('resolves the extension registered by AppTheme.dark()', (tester) async {
      late AppSemanticColors resolved;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Builder(
            builder: (context) {
              resolved = AppSemanticColors.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(resolved.success, AppSemanticColors.dark.success);
    });
  });
}
