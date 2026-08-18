import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/app_routes.dart';
import '../../../../core/presentation/widgets/app_card.dart';
import '../../../../core/presentation/widgets/app_top_bar.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../instances/application/instance_list_controller.dart';

/// Settings hub — Konto / Połączenie / Aplikacja / Bezpieczeństwo /
/// Informacje, each a group of tiles pushing a dedicated sub-screen.
/// Mirrors the structure requested for a real client app's settings
/// surface; sections without a working backend yet (Konto,
/// Bezpieczeństwo) still route to a real screen, which shows an honest
/// [ComingSoonView] rather than omitting the destination entirely.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeInstance = ref.watch(instanceListControllerProvider).value?.activeInstance;

    return Scaffold(
      appBar: const AppTopBar(title: 'Więcej'),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        children: [
          _SettingsGroup(
            title: 'Konto',
            tiles: [
              _SettingsTile(
                icon: Icons.person_outline,
                title: 'Profil',
                subtitle: 'Wkrótce',
                onTap: () => context.push(AppRoutes.settingsAccount),
              ),
            ],
          ),
          _SettingsGroup(
            title: 'Połączenie',
            tiles: [
              _SettingsTile(
                icon: Icons.dns_outlined,
                title: 'Panele',
                subtitle: activeInstance != null ? 'Aktywny: ${activeInstance.name}' : 'Brak aktywnego panelu',
                onTap: () => context.push(AppRoutes.settingsConnections),
              ),
            ],
          ),
          _SettingsGroup(
            title: 'Control Plane',
            tiles: [
              _SettingsTile(
                icon: Icons.hub_outlined,
                title: 'Konto Control Plane',
                subtitle: 'Zarządzaj serwerami z wielu paneli przez jedno konto',
                onTap: () => context.push(AppRoutes.settingsControlPlane),
              ),
            ],
          ),
          _SettingsGroup(
            title: 'Aplikacja',
            tiles: [
              _SettingsTile(
                icon: Icons.palette_outlined,
                title: 'Wygląd',
                subtitle: 'Motyw jasny / ciemny / systemowy',
                onTap: () => context.push(AppRoutes.settingsApplication),
              ),
            ],
          ),
          _SettingsGroup(
            title: 'Bezpieczeństwo',
            tiles: [
              _SettingsTile(
                icon: Icons.lock_outline,
                title: 'Blokada biometryczna',
                subtitle: 'Wkrótce',
                onTap: () => context.push(AppRoutes.settingsSecurity),
              ),
            ],
          ),
          _SettingsGroup(
            title: 'Informacje',
            tiles: [
              _SettingsTile(
                icon: Icons.info_outline,
                title: 'O aplikacji',
                subtitle: 'Wersja, licencje',
                onTap: () => context.push(AppRoutes.settingsAbout),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.title, required this.tiles});

  final String title;
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: AppSpacing.xs, bottom: AppSpacing.xxs),
            child: Text(
              title.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
                letterSpacing: 0.8,
              ),
            ),
          ),
          AppCard(padding: EdgeInsets.zero, child: Column(children: tiles)),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({required this.icon, required this.title, required this.subtitle, required this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
