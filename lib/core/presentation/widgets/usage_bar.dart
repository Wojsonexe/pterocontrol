import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_surface_colors.dart';

/// A thin labeled usage bar — "CPU 34%", "RAM 1.2 / 4 GB" — for anywhere
/// a live resource reading has both a proportion (0.0-1.0, drawn as the
/// fill) and a value worth reading as text. The visual vocabulary of an
/// actual monitoring tool (a filled track, not just a number), which is
/// exactly what `ServerCard`'s live section needed to stop reading as a
/// static spec sheet.
///
/// [ratio] is clamped to [0, 1] — a reading that technically exceeds the
/// configured limit (bursting past a soft CPU cap, for instance) still
/// draws a full bar rather than overflowing the track; the exact number
/// is still in [valueLabel].
class UsageBar extends StatelessWidget {
  const UsageBar({super.key, required this.label, required this.valueLabel, required this.ratio, required this.color});

  final String label;
  final String valueLabel;
  final double ratio;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaces = AppSurfaceColors.of(context);
    final clamped = ratio.isFinite ? ratio.clamp(0.0, 1.0) : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(color: surfaces.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const Spacer(),
            Text(
              valueLabel,
              style: theme.textTheme.labelSmall?.copyWith(color: surfaces.textPrimary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.full),
          child: SizedBox(
            height: 4,
            child: Stack(
              children: [
                ColoredBox(color: surfaces.surfaceActive),
                AnimatedFractionallySizedBox(
                  duration: AppMotion.medium,
                  curve: AppMotion.curve,
                  alignment: Alignment.centerLeft,
                  widthFactor: clamped,
                  child: ColoredBox(color: color),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
