import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pterodactyl_mobile/core/theme/app_semantic_colors.dart';
import 'package:pterodactyl_mobile/core/theme/app_status_tokens.dart';

void main() {
  group('AppStatusTone.resolve', () {
    test('success resolves to AppSemanticColors.success/onSuccess/...', () {
      final result = AppStatusTone.success.resolve(AppSemanticColors.light);
      expect(result.color, AppSemanticColors.light.success);
      expect(result.onColor, AppSemanticColors.light.onSuccess);
      expect(result.container, AppSemanticColors.light.successContainer);
      expect(result.onContainer, AppSemanticColors.light.onSuccessContainer);
    });

    test('pending resolves to AppSemanticColors.pending/onPending/...', () {
      final result = AppStatusTone.pending.resolve(AppSemanticColors.light);
      expect(result.color, AppSemanticColors.light.pending);
    });

    test('danger resolves to AppSemanticColors.danger/onDanger/...', () {
      final result = AppStatusTone.danger.resolve(AppSemanticColors.light);
      expect(result.color, AppSemanticColors.light.danger);
    });

    test('neutral resolves to AppSemanticColors.neutral/onNeutral/...', () {
      final result = AppStatusTone.neutral.resolve(AppSemanticColors.light);
      expect(result.color, AppSemanticColors.light.neutral);
    });

    test('resolves independently against light vs dark presets', () {
      final light = AppStatusTone.success.resolve(AppSemanticColors.light);
      final dark = AppStatusTone.success.resolve(AppSemanticColors.dark);
      expect(light.color, isNot(dark.color));
    });
  });

  group('AppStatusVisual', () {
    test('equality is value-based', () {
      const a = AppStatusVisual(icon: Icons.check_circle, label: 'Online', tone: AppStatusTone.success);
      const b = AppStatusVisual(icon: Icons.check_circle, label: 'Online', tone: AppStatusTone.success);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('isAnimated defaults to false', () {
      const visual = AppStatusVisual(icon: Icons.check_circle, label: 'Online', tone: AppStatusTone.success);
      expect(visual.isAnimated, isFalse);
    });

    test('instances differing by isAnimated are not equal', () {
      const a = AppStatusVisual(icon: Icons.sync, label: 'Sprawdzanie…', tone: AppStatusTone.pending);
      const b = AppStatusVisual(
        icon: Icons.sync,
        label: 'Sprawdzanie…',
        tone: AppStatusTone.pending,
        isAnimated: true,
      );
      expect(a, isNot(equals(b)));
    });
  });
}
