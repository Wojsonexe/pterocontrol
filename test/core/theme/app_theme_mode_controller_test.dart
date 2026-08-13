import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pterodactyl_mobile/app/app_provider_policy.dart';
import 'package:pterodactyl_mobile/core/storage/shared_preferences_provider.dart';
import 'package:pterodactyl_mobile/core/theme/app_theme_mode_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _buildContainer({Map<String, Object> initialPrefs = const {}}) async {
  SharedPreferences.setMockInitialValues(initialPrefs);
  final preferences = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    retry: noAutomaticProviderRetry,
    overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
  );
  return container;
}

void main() {
  group('AppThemeModeController.build', () {
    test('defaults to ThemeMode.system when nothing is stored', () async {
      final container = await _buildContainer();
      addTearDown(container.dispose);

      expect(container.read(appThemeModeControllerProvider), ThemeMode.system);
    });

    test('reads a previously persisted mode', () async {
      final container = await _buildContainer(initialPrefs: {AppThemeModeController.prefsKey: 'dark'});
      addTearDown(container.dispose);

      expect(container.read(appThemeModeControllerProvider), ThemeMode.dark);
    });

    test('falls back to system for an unrecognized stored value', () async {
      final container = await _buildContainer(initialPrefs: {AppThemeModeController.prefsKey: 'garbage'});
      addTearDown(container.dispose);

      expect(container.read(appThemeModeControllerProvider), ThemeMode.system);
    });
  });

  group('AppThemeModeController.setThemeMode', () {
    test('updates state immediately', () async {
      final container = await _buildContainer();
      addTearDown(container.dispose);

      await container.read(appThemeModeControllerProvider.notifier).setThemeMode(ThemeMode.light);

      expect(container.read(appThemeModeControllerProvider), ThemeMode.light);
    });

    test('persists so a fresh controller reads the new value back', () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();

      final first = ProviderContainer(
        retry: noAutomaticProviderRetry,
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
      );
      await first.read(appThemeModeControllerProvider.notifier).setThemeMode(ThemeMode.dark);
      first.dispose();

      final second = ProviderContainer(
        retry: noAutomaticProviderRetry,
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
      );
      addTearDown(second.dispose);

      expect(second.read(appThemeModeControllerProvider), ThemeMode.dark);
    });
  });
}
