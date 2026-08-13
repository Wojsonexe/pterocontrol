import 'package:flutter/material.dart';

import '../../theme/app_spacing.dart';
import '../../theme/app_surface_colors.dart';
import '../../theme/app_typography.dart';
import 'app_card.dart';

/// A single glanceable statistic as its own small card — the Dashboard's
/// building block for "how many servers are active", "how many need
/// attention", etc. Distinct from [MetricGrid]/[MetricItem] (dense
/// icon+label+value *rows*, used on `ServerDetailScreen` for a longer
/// list of configured/live values): this is a standalone tile sized to
/// carry one number with real visual weight, for the handful of numbers
/// that deserve to be the first thing a user's eye lands on.
class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.color,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;

  /// Tints the icon/value — omit for a neutral metric (e.g. "total"),
  /// pass a semantic color for one that means something (danger for
  /// "needs attention").
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaces = AppSurfaceColors.of(context);
    final tint = color ?? surfaces.textPrimary;

    return AppCard(
      onTap: onTap,
      semanticLabel: '$label: $value',
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: tint),
          const SizedBox(height: AppSpacing.sm),
          Text(
            value,
            style: AppTypography.metricNumber.copyWith(fontSize: 24, color: surfaces.textPrimary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(color: surfaces.textSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
