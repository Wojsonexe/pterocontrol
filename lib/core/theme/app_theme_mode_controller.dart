import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/shared_preferences_provider.dart';

/// Persisted user preference for [ThemeMode] (system/light/dark) — surfaced
/// in Settings > Aplikacja.
///
/// Stored directly via [SharedPreferences] (not secret data, same tier as
/// instance metadata) rather than through a dedicated feature layer: this
/// is a single UI preference, not a business domain with its own
/// repository/API — a full domain/data/application split here would be
/// ceremony without benefit.
class AppThemeModeController extends Notifier<ThemeMode> {
  static const prefsKey = 'settings.theme_mode.v1';

  @override
  ThemeMode build() {
    final raw = ref.watch(sharedPreferencesProvider).getString(prefsKey);
    return switch (raw) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    await ref.read(sharedPreferencesProvider).setString(prefsKey, mode.name);
  }
}

final appThemeModeControllerProvider = NotifierProvider<AppThemeModeController, ThemeMode>(
  AppThemeModeController.new,
);
