import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_mode_controller.dart';

/// Real, working setting: light/dark/system theme — persisted via
/// [AppThemeModeController] (`SharedPreferences`), read by
/// `PterodactylMobileApp` on every rebuild.
class ApplicationSettingsScreen extends ConsumerWidget {
  const ApplicationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(appThemeModeControllerProvider);
    final notifier = ref.read(appThemeModeControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Wygląd')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Text('Motyw', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          Card(
            margin: EdgeInsets.zero,
            child: RadioGroup<ThemeMode>(
              groupValue: mode,
              onChanged: (value) => notifier.setThemeMode(value!),
              child: const Column(
                children: [
                  RadioListTile<ThemeMode>(
                    title: Text('Systemowy'),
                    subtitle: Text('Dopasuj do ustawień telefonu'),
                    value: ThemeMode.system,
                  ),
                  RadioListTile<ThemeMode>(
                    title: Text('Jasny'),
                    value: ThemeMode.light,
                  ),
                  RadioListTile<ThemeMode>(
                    title: Text('Ciemny'),
                    value: ThemeMode.dark,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
