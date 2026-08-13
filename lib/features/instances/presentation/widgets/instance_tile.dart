import 'package:flutter/material.dart';

import '../../../../core/presentation/widgets/app_card.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_surface_colors.dart';
import '../../domain/pterodactyl_instance.dart';
import 'connection_status_chip.dart';

enum InstanceTileAction { checkConnection, delete }

/// A single row in [InstancesScreen]'s list: identity, URL, connection
/// status, and an overflow menu for secondary actions. The active
/// instance gets the brand-accent treatment (tinted avatar, accent bar,
/// a filled "Aktywna" pill) so it reads as *the one currently in use*
/// at a glance, not just a small star icon next to identical rows.
class InstanceTile extends StatelessWidget {
  const InstanceTile({
    super.key,
    required this.instance,
    required this.isActive,
    required this.onTap,
    required this.onAction,
  });

  final PterodactylInstance instance;
  final bool isActive;
  final VoidCallback onTap;
  final ValueChanged<InstanceTileAction> onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaces = AppSurfaceColors.of(context);
    final initial = instance.name.isNotEmpty ? instance.name[0].toUpperCase() : '?';
    final accent = isActive ? theme.colorScheme.primary : null;

    return AppCard(
      onTap: onTap,
      elevated: isActive,
      accent: accent,
      semanticLabel: isActive ? '${instance.name}, aktywna instancja' : instance.name,
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.xs, AppSpacing.sm),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isActive ? theme.colorScheme.primary : surfaces.surfaceActive,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              initial,
              style: theme.textTheme.titleMedium?.copyWith(
                color: isActive ? theme.colorScheme.onPrimary : surfaces.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        instance.name,
                        style: theme.textTheme.titleMedium?.copyWith(color: surfaces.textPrimary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isActive) ...[
                      const SizedBox(width: AppSpacing.xxs),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'AKTYWNA',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer,
                            fontSize: 9,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  instance.baseUrl,
                  style: theme.textTheme.bodySmall?.copyWith(color: surfaces.textSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.xs),
                ConnectionStatusChip(status: instance.connectionStatus, dense: true),
              ],
            ),
          ),
          PopupMenuButton<InstanceTileAction>(
            tooltip: 'Więcej opcji',
            onSelected: onAction,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: InstanceTileAction.checkConnection,
                child: ListTile(
                  leading: Icon(Icons.refresh),
                  title: Text('Sprawdź połączenie'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: InstanceTileAction.delete,
                child: ListTile(
                  leading: Icon(Icons.delete_outline),
                  title: Text('Usuń'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
