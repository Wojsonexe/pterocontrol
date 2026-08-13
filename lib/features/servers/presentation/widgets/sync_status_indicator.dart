import 'package:flutter/material.dart';

import '../../../../core/presentation/widgets/status_dot.dart';
import '../../../../core/theme/app_semantic_colors.dart';
import '../../../../core/theme/app_surface_colors.dart';
import '../../application/server_runtime_sync_state.dart';

/// Small, glanceable "is the list actually live" indicator for a
/// server-list-style screen's header — a plain [StatusDot] plus a tiny
/// label, deliberately with **no** pill/container background. A colored
/// badge here reads as a debug flag bolted onto the header; a small dot
/// that quietly sits next to the title reads as part of the app's own
/// chrome — this is the whole point of "ma wyglądać jak część aplikacji,
/// a nie debug information".
///
/// Three states, always shown (never hidden): [ServerSyncStatus.syncing]
/// covers both "never synced yet" (app just opened) and "recovering after
/// a failure" — both are honestly the same thing from the user's point of
/// view, "trying to get a fresh read right now", so both read as
/// "Łączenie…" rather than one being silently invisible.
class SyncStatusIndicator extends StatelessWidget {
  const SyncStatusIndicator({super.key, required this.status});

  final ServerSyncStatus status;

  @override
  Widget build(BuildContext context) {
    final semantic = AppSemanticColors.of(context);
    final surfaces = AppSurfaceColors.of(context);
    final theme = Theme.of(context);

    final (Color color, String label, bool pulsing) = switch (status) {
      ServerSyncStatus.syncing => (surfaces.textTertiary, 'Łączenie…', false),
      ServerSyncStatus.live => (semantic.info, 'Na żywo', true),
      ServerSyncStatus.offline => (semantic.danger, 'Offline', false),
    };

    return Semantics(
      label: 'Stan synchronizacji: $label',
      excludeSemantics: true,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
        child: Row(
          key: ValueKey(status),
          mainAxisSize: MainAxisSize.min,
          children: [
            StatusDot(color: color, size: 6, pulsing: pulsing),
            const SizedBox(width: 5),
            Text(label, style: theme.textTheme.labelSmall?.copyWith(color: surfaces.textSecondary)),
          ],
        ),
      ),
    );
  }
}
