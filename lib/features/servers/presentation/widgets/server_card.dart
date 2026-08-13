import 'package:flutter/material.dart';

import '../../../../core/formatting/metric_formatting.dart';
import '../../../../core/presentation/widgets/app_card.dart';
import '../../../../core/presentation/widgets/app_status_badge.dart';
import '../../../../core/presentation/widgets/skeleton_box.dart';
import '../../../../core/presentation/widgets/usage_bar.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_semantic_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status_tokens.dart';
import '../../../../core/theme/app_surface_colors.dart';
import '../../domain/server.dart';
import '../../domain/server_metrics_history.dart';
import '../../domain/server_runtime_state.dart';
import 'effective_server_status.dart';

/// One server, as a real monitoring-tool row rather than a plain
/// rectangle: an identity row (icon mark, name, node, chevron), one
/// unambiguous status badge (see `effectiveServerStatus`, which resolves
/// administrative + live power state into a single answer instead of two
/// badges the reader has to reconcile themselves), and — once a reading
/// has actually arrived — filled CPU/RAM usage bars plus a compact
/// network-rate/uptime line, instead of static configured-limit numbers.
/// This is the single place Dashboard/Servers render a server; there is
/// deliberately no second, slightly-different card implementation for
/// either screen.
///
/// [runtimeState]/[history] are optional; `null`/no reading yet falls
/// back to a placeholder (skeleton while the first fetch is in flight, a
/// quiet `—` otherwise) — a card must never show blank space just because
/// a poll has not landed yet, and must never *lose* a value it already
/// has just because a refresh for it is currently in flight or just
/// failed — see [isRefreshing]/[hasRecentFailure], sourced from
/// `ServerRuntimeSyncState.isRefreshing`/`hasRecentFailure` (that state
/// keeps the last-good [runtimeState] untouched during both cases; this
/// card only adds a small, secondary indicator on top of it).
/// [AppStatusBadge] already cross-fades between two different
/// [effectiveServerStatus] results on its own (`installing` → `running`
/// reads as a smooth badge swap, not a hard cut) — nothing extra is
/// needed here for that.
class ServerCard extends StatelessWidget {
  const ServerCard({
    super.key,
    required this.server,
    required this.onTap,
    this.runtimeState,
    this.history,
    this.isRefreshing = false,
    this.hasRecentFailure = false,
    this.index = 0,
  });

  final Server server;
  final VoidCallback onTap;
  final ServerRuntimeState? runtimeState;
  final ServerMetricsHistory? history;

  /// Whether this server's `.../resources` fetch is *currently* in
  /// flight. Never clears [runtimeState] on its own — a refresh in
  /// progress keeps showing whatever was last known, plus a small
  /// secondary indicator.
  final bool isRefreshing;

  /// Whether the most recent fetch attempt for this server failed. Shown
  /// as a small "Nie udało się odświeżyć" caption alongside whatever data
  /// is already known (or `—` if there never was any) — never as a
  /// reason to hide/replace [runtimeState].
  final bool hasRecentFailure;

  /// Position in its list — purely cosmetic (see `FadeSlideIn`'s stagger);
  /// has no effect on layout or data.
  final int index;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaces = AppSurfaceColors.of(context);
    final semantic = AppSemanticColors.of(context);
    final hasLiveReading = runtimeState != null && runtimeState!.hasResourceReading;
    final visual = effectiveServerStatus(
      administrativeStatus: server.status,
      powerState: runtimeState?.powerState,
    );
    final accent = visual.tone.resolve(semantic).color;

    return AppCard(
      onTap: onTap,
      accent: accent,
      semanticLabel: '${server.name}, ${visual.label}, węzeł ${server.node}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Mark(color: accent),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      server.name,
                      style: theme.textTheme.titleMedium?.copyWith(color: surfaces.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      server.description?.isNotEmpty ?? false ? server.description! : server.node,
                      style: theme.textTheme.bodySmall?.copyWith(color: surfaces.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Icon(Icons.chevron_right_rounded, color: surfaces.textTertiary),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              AppStatusBadge(visual: visual, dense: true),
              if (server.isTransferring) ...[
                const SizedBox(width: AppSpacing.xxs),
                Icon(Icons.sync_alt_rounded, size: 14, color: surfaces.textTertiary),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          hasLiveReading
              ? _LiveMetrics(
                  server: server,
                  runtimeState: runtimeState!,
                  latestSample: history?.latest,
                  isRefreshing: isRefreshing,
                  hasRecentFailure: hasRecentFailure,
                )
              : _PendingMetricsRow(server: server, isRefreshing: isRefreshing, hasRecentFailure: hasRecentFailure),
        ],
      ),
    );
  }
}

/// Rounded-square server mark — deliberately not a circular initial-letter
/// avatar (that reads as a *person*, not a *server*); a plain tinted icon
/// mark reads as infrastructure at a glance.
class _Mark extends StatelessWidget {
  const _Mark({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.sm)),
      child: Icon(Icons.dns_rounded, size: 20, color: color),
    );
  }
}

class _LiveMetrics extends StatelessWidget {
  const _LiveMetrics({
    required this.server,
    required this.runtimeState,
    required this.latestSample,
    required this.isRefreshing,
    required this.hasRecentFailure,
  });

  final Server server;
  final ServerRuntimeState runtimeState;
  final MetricSample? latestSample;
  final bool isRefreshing;
  final bool hasRecentFailure;

  @override
  Widget build(BuildContext context) {
    final semantic = AppSemanticColors.of(context);
    final cpuLimit = server.limits.cpuPercent > 0 ? server.limits.cpuPercent : 100;
    final cpuValue = runtimeState.cpuAbsolutePercent ?? 0;
    final memoryLimitBytes = server.limits.memoryMb * 1024 * 1024;
    final memoryValue = runtimeState.memoryBytes ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: UsageBar(
                label: 'CPU',
                valueLabel: '${cpuValue.round()}%',
                ratio: cpuValue / cpuLimit,
                color: semantic.info,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: UsageBar(
                label: 'RAM',
                valueLabel: formatBytesAsMb(memoryValue),
                ratio: memoryLimitBytes > 0 ? memoryValue / memoryLimitBytes : 0,
                color: semantic.info,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        // `Wrap`, not `Row`+`Spacer`: at large accessibility text scales or
        // on a narrow phone, three icon+text pairs can outgrow one line —
        // wrapping to a second line beats a clipped/overflowing row.
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _InlineStat(icon: Icons.arrow_upward_rounded, value: formatRate(latestSample?.networkTxRateBytesPerSecond)),
            _InlineStat(icon: Icons.arrow_downward_rounded, value: formatRate(latestSample?.networkRxRateBytesPerSecond)),
            if (runtimeState.uptimeMs != null)
              _InlineStat(icon: Icons.schedule_rounded, value: formatUptime(runtimeState.uptimeMs!)),
          ],
        ),
        _MetricsMeta(isRefreshing: isRefreshing, hasRecentFailure: hasRecentFailure, observedAt: runtimeState.observedAt),
      ],
    );
  }
}

/// Small, secondary line under an already-populated card's metrics —
/// never a reason to hide the values above it. Exactly one of three
/// things at a time, in priority order: a failed refresh (data shown is
/// stale *because* the last attempt to update it didn't work), an
/// in-progress refresh (data shown is about to be replaced), or — the
/// steady-state case — how long ago the data shown was actually
/// observed, so "27%" never silently implies "right now" once it's a
/// minute old.
class _MetricsMeta extends StatelessWidget {
  const _MetricsMeta({required this.isRefreshing, required this.hasRecentFailure, required this.observedAt});

  final bool isRefreshing;
  final bool hasRecentFailure;
  final DateTime? observedAt;

  @override
  Widget build(BuildContext context) {
    final surfaces = AppSurfaceColors.of(context);
    final semantic = AppSemanticColors.of(context);
    final theme = Theme.of(context);
    final style = theme.textTheme.labelSmall?.copyWith(color: surfaces.textTertiary);

    Widget? content;
    if (hasRecentFailure) {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, size: 12, color: semantic.pending),
          const SizedBox(width: 2),
          Text('Nie udało się odświeżyć', style: style?.copyWith(color: semantic.pending)),
        ],
      );
    } else if (isRefreshing) {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(strokeWidth: 1.5, color: surfaces.textTertiary),
          ),
          const SizedBox(width: 4),
          Text('Aktualizowanie…', style: style),
        ],
      );
    } else if (observedAt != null) {
      content = Text(formatRelativeTime(observedAt!), style: style);
    }

    if (content == null) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.only(top: 4), child: content);
  }
}

class _InlineStat extends StatelessWidget {
  const _InlineStat({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    final surfaces = AppSurfaceColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: surfaces.textTertiary),
        const SizedBox(width: 2),
        Text(value, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: surfaces.textSecondary)),
      ],
    );
  }
}

/// Shown before this server's first-ever resource reading has arrived.
/// Configured limits (memory/disk) stay on the left — real, known numbers
/// — while the right side reflects exactly what's happening: a pulsing
/// skeleton while the first fetch is in flight, a quiet `—` once it's
/// clear nothing is coming *right now* (not "the app is stuck"), or a
/// small failure caption if the first attempt already came back and
/// failed.
class _PendingMetricsRow extends StatelessWidget {
  const _PendingMetricsRow({required this.server, required this.isRefreshing, required this.hasRecentFailure});

  final Server server;
  final bool isRefreshing;
  final bool hasRecentFailure;

  @override
  Widget build(BuildContext context) {
    final surfaces = AppSurfaceColors.of(context);
    final semantic = AppSemanticColors.of(context);
    final theme = Theme.of(context);

    Widget stat(IconData icon, String value) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: surfaces.textTertiary),
            const SizedBox(width: AppSpacing.xxs),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(color: surfaces.textSecondary),
            ),
          ],
        );

    final Widget trailing;
    if (isRefreshing) {
      trailing = const SkeletonBox(width: 64, height: 12);
    } else if (hasRecentFailure) {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, size: 12, color: semantic.pending),
          const SizedBox(width: 2),
          Text(
            'Nie udało się odświeżyć',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(color: semantic.pending),
          ),
        ],
      );
    } else {
      trailing = Text('—', style: theme.textTheme.labelSmall?.copyWith(color: surfaces.textTertiary));
    }

    return Row(
      children: [
        stat(Icons.memory_outlined, '${server.limits.memoryMb} MB'),
        const SizedBox(width: AppSpacing.md),
        stat(Icons.storage_outlined, '${server.limits.diskMb} MB'),
        const SizedBox(width: AppSpacing.xs),
        // `Expanded`, not `Spacer()`+a fixed-size trailing widget: with
        // large configured limits (long "123456 MB" strings) or a narrow
        // phone, a fixed-size trailing widget had nowhere to shrink and
        // overflowed the row — this instead claims whatever width is left
        // over (possibly very little) and aligns to the right within it.
        Expanded(child: Align(alignment: Alignment.centerRight, child: trailing)),
      ],
    );
  }
}
