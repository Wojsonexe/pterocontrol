import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_surface_colors.dart';

@immutable
class AppBottomNavItem {
  const AppBottomNavItem({required this.icon, required this.activeIcon, required this.label});

  final IconData icon;
  final IconData activeIcon;
  final String label;
}

/// The app's bottom navigation — replaces the stock [NavigationBar] (four
/// default M3 icon/label pairs, visually identical to any other Material
/// app's tab bar) with a bar built specifically for this app: a hairline
/// top edge instead of a shadow, and the selected destination shown as a
/// filled, labeled pill against otherwise icon-first inactive items,
/// rather than every destination fighting for the same weight regardless
/// of state.
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({super.key, required this.items, required this.currentIndex, required this.onSelect});

  final List<AppBottomNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final surfaces = AppSurfaceColors.of(context);
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: surfaces.surfaceElevated,
        border: Border(top: BorderSide(color: surfaces.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: _NavItem(
                    item: items[i],
                    selected: i == currentIndex,
                    onTap: () => onSelect(i),
                    theme: theme,
                    surfaces: surfaces,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.item,
    required this.selected,
    required this.onTap,
    required this.theme,
    required this.surfaces,
  });

  final AppBottomNavItem item;
  final bool selected;
  final VoidCallback onTap;
  final ThemeData theme;
  final AppSurfaceColors surfaces;

  @override
  Widget build(BuildContext context) {
    final color = selected ? theme.colorScheme.primary : surfaces.textTertiary;

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.full),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
          child: AnimatedContainer(
            duration: AppMotion.medium,
            curve: AppMotion.curve,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? theme.colorScheme.primaryContainer : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  selected ? item.activeIcon : item.icon,
                  size: 22,
                  color: selected ? theme.colorScheme.onPrimaryContainer : color,
                ),
                const SizedBox(height: 2),
                Text(
                  item.label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: selected ? theme.colorScheme.onPrimaryContainer : color,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
