import 'package:flutter/material.dart';

import '../../theme/app_radius.dart';
import '../../theme/app_semantic_colors.dart';
import '../../theme/app_status_tokens.dart';

/// The single, shared status-badge visual used everywhere the app shows
/// "how is this doing" (instance connection, server administrative
/// status, server power state, console connection state) — replaces
/// three previously-independent implementations
/// (`ConnectionStatusChip`/`ServerStatusChip`/console's private status
/// indicator) with one component reading an [AppStatusVisual].
///
/// Never relies on color alone: icon (or an animated spinner, for
/// [AppStatusVisual.isAnimated] states) plus text always accompany the
/// color, and the whole badge merges into a single [Semantics] node so a
/// screen reader announces the label once, not "icon, then text".
///
/// Transitions between two different [AppStatusVisual]s (e.g. a
/// WebSocket going `connecting` → `connected`) cross-fade instead of
/// changing instantly — this app's connection states can flip a few
/// times a second during a reconnect storm, and an instant swap read as
/// flicker. Skipped entirely when the platform requests reduced motion.
class AppStatusBadge extends StatelessWidget {
  const AppStatusBadge({super.key, required this.visual, this.dense = false});

  final AppStatusVisual visual;

  /// Tighter padding/icon size — for inline use next to other compact
  /// controls (e.g. a screen header) instead of inside a list tile.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final colors = visual.tone.resolve(AppSemanticColors.of(context));
    final iconSize = dense ? 14.0 : 16.0;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    final content = Container(
      key: ValueKey(visual),
      padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 10, vertical: dense ? 4 : 6),
      decoration: BoxDecoration(
        color: colors.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (visual.isAnimated)
            SizedBox(
              width: iconSize,
              height: iconSize,
              child: CircularProgressIndicator(strokeWidth: 2, color: colors.color),
            )
          else
            Icon(visual.icon, size: iconSize, color: colors.color),
          const SizedBox(width: 6),
          Text(
            visual.label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(color: colors.color),
          ),
        ],
      ),
    );

    return Semantics(
      label: visual.label,
      child: ExcludeSemantics(
        child: reduceMotion
            ? content
            : AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
                child: content,
              ),
      ),
    );
  }
}
