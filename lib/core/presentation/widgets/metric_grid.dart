import 'package:flutter/material.dart';

import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_surface_colors.dart';
import '../../theme/app_typography.dart';

/// One resource metric (icon, label, value) — an item in a [MetricGrid].
@immutable
class MetricItem {
  const MetricItem({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;
}

/// A compact 2-column grid of [MetricItem]s — replaces a stack of
/// `ListTile`s (which reads as a Settings screen, not a glanceable
/// summary) for a handful of at-a-glance numbers (node, RAM, disk, CPU,
/// ...).
///
/// Deliberately laid out with plain `Row`/`Column` instead of `GridView`
/// with a fixed `childAspectRatio`: a fixed aspect ratio does not grow
/// with the user's text-scale setting and can clip at large accessibility
/// font sizes, which this layout avoids by sizing each tile to its own
/// content.
class MetricGrid extends StatelessWidget {
  const MetricGrid({super.key, required this.items});

  final List<MetricItem> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < items.length; i += 2)
          Padding(
            padding: EdgeInsets.only(bottom: i + 2 < items.length ? AppSpacing.sm : 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _MetricTile(item: items[i])),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: i + 1 < items.length ? _MetricTile(item: items[i + 1]) : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.item});

  final MetricItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaces = AppSurfaceColors.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: surfaces.surfaceActive,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Semantics(
          label: '${item.label}: ${item.value}',
          child: ExcludeSemantics(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(item.icon, size: 20, color: surfaces.textSecondary),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.label,
                        style: theme.textTheme.labelSmall?.copyWith(color: surfaces.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        item.value,
                        style: AppTypography.metricNumber.copyWith(fontSize: 16, color: surfaces.textPrimary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
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
