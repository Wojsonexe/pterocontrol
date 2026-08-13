import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';

/// Real app version (matches `pubspec.yaml`, kept in sync by hand — this
/// app has no `package_info_plus` dependency, and adding one only to read
/// a version string that is already known at build time is not worth a
/// new dependency).
const _appVersion = '1.0.0';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('O aplikacji')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Center(
            child: Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(color: theme.colorScheme.primaryContainer, shape: BoxShape.circle),
                  child: Icon(Icons.dns_rounded, size: 36, color: theme.colorScheme.onPrimaryContainer),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text('Pterodactyl Mobile', style: theme.textTheme.titleLarge),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  'Wersja $_appVersion',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Licencje open source'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showLicensePage(
                context: context,
                applicationName: 'Pterodactyl Mobile',
                applicationVersion: _appVersion,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
