import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/app_routes.dart';
import '../../../../core/error/app_exception.dart';
import '../../../../core/formatting/metric_formatting.dart';
import '../../../../core/presentation/widgets/app_card.dart';
import '../../../../core/presentation/widgets/app_top_bar.dart';
import '../../../../core/presentation/widgets/error_view.dart';
import '../../../../core/presentation/widgets/fade_slide_in.dart';
import '../../../../core/presentation/widgets/skeleton_box.dart';
import '../../../../core/presentation/widgets/sparkline.dart';
import '../../../../core/presentation/widgets/status_dot.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_semantic_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_surface_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../instances/application/instance_list_controller.dart';
import '../../../servers/application/server_list_controller.dart';
import '../../../servers/application/server_runtime_sync_controller.dart';
import '../../../servers/application/server_runtime_sync_state.dart';
import '../../../servers/domain/server.dart';
import '../../../servers/domain/server_power_state.dart';
import '../../../servers/domain/server_runtime_state.dart';
import '../../../servers/presentation/widgets/server_card.dart';
import '../../../servers/presentation/widgets/sync_status_indicator.dart';

/// Landing tab once a panel is active — the app's control-room view: one
/// glance answers "is my infrastructure healthy", "what's using
/// resources right now", and "which servers actually need me". Every
/// number on this screen comes from `ServerListController`/
/// `ServerRuntimeSyncController` — nothing here is invented to fill
/// space, including the resource sparklines (a short *real* rolling
/// history of samples this session has actually observed — see
/// `ServerMetricsHistory` — never a synthesized trend).
///
/// Deliberately does **not** show a "recent activity" feed — there is no
/// activity-log/notifications API behind this app yet (see "Alerty"
/// tab); inventing one here would be exactly the fake data this screen
/// must not have.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final instanceState = ref.watch(instanceListControllerProvider);
    final activeInstance = instanceState.value?.activeInstance;
    final syncStatus = activeInstance == null
        ? null
        : ref.watch(serverRuntimeSyncControllerProvider(activeInstance.id).select((s) => s.status));
    final servers = activeInstance == null
        ? null
        : ref.watch(serverListControllerProvider(activeInstance.id).select((s) => s.value?.servers));

    return Scaffold(
      appBar: AppTopBar(
        title: activeInstance?.name ?? 'Panel',
        subtitle: activeInstance == null ? null : _headerSummary(servers),
        trailing: activeInstance == null
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SyncStatusIndicator(status: syncStatus ?? ServerSyncStatus.syncing),
                  const SizedBox(width: AppSpacing.xs),
                  Tooltip(
                    message: 'Zmień panel',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.full),
                      onTap: () => context.push(AppRoutes.settingsConnections),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(Icons.swap_horiz_rounded, size: 20, color: AppSurfaceColors.of(context).textSecondary),
                      ),
                    ),
                  ),
                ],
              ),
      ),
      body: activeInstance == null ? const _NoActiveInstance() : _DashboardBody(instanceId: activeInstance.id),
    );
  }

  /// A one-line health summary for the header subtitle — "3 serwery,
  /// wszystko działa" / "3 serwery, 1 wymaga uwagi" — computed from
  /// already-loaded data, so requirement #1 ("jaki jest ogólny stan
  /// infrastruktury") is answered before the user even scrolls. `null`
  /// while the list is still loading — [AppTopBar] simply omits the
  /// subtitle line then, rather than showing a stale/guessed count.
  String? _headerSummary(List<Server>? servers) {
    if (servers == null) return null;
    if (servers.isEmpty) return 'Brak serwerów';
    final attention = servers.where((s) => s.status != ServerAdministrativeStatus.active).length;
    final serverWord = servers.length == 1 ? 'serwer' : 'serwerów';
    if (attention == 0) return '${servers.length} $serverWord • wszystko działa';
    return '${servers.length} $serverWord • $attention wymaga uwagi';
  }
}

class _NoActiveInstance extends StatelessWidget {
  const _NoActiveInstance();

  @override
  Widget build(BuildContext context) {
    // Defensive only — RootScreen never mounts the shell without an
    // active instance. Shown if the active panel is removed from
    // Więcej -> Połączenia while the Dashboard tab is still mounted
    // underneath, before the shell has a chance to redirect.
    return Center(
      child: FilledButton.icon(
        onPressed: () => context.go(AppRoutes.settingsConnections),
        icon: const Icon(Icons.dns_outlined),
        label: const Text('Wybierz panel'),
      ),
    );
  }
}

class _DashboardBody extends ConsumerWidget {
  const _DashboardBody({required this.instanceId});

  final String instanceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(serverListControllerProvider(instanceId));
    // Keeps the sync controller alive for as long as this screen is
    // visible, regardless of whether the `data` branch below is currently
    // built — watched here (not inside `_DashboardContent`) so a loading
    // or error state does not tear down polling that was already warmed up.
    final syncState = ref.watch(serverRuntimeSyncControllerProvider(instanceId));

    return RefreshIndicator(
      onRefresh: () => ref.read(serverListControllerProvider(instanceId).notifier).refresh(),
      child: state.when(
        data: (data) => _DashboardContent(instanceId: instanceId, servers: data.servers, syncState: syncState),
        loading: () => const _DashboardSkeleton(),
        error: (error, stackTrace) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: 420,
              child: ErrorView(
                message: error is AppException ? error.message : 'Nie udało się wczytać serwerów.',
                onRetry: () => ref.invalidate(serverListControllerProvider(instanceId)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardContent extends StatelessWidget {
  const _DashboardContent({required this.instanceId, required this.servers, required this.syncState});

  final String instanceId;
  final List<Server> servers;
  final ServerRuntimeSyncState syncState;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaces = AppSurfaceColors.of(context);

    if (servers.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [SizedBox(height: 480, child: _NoServersYet())],
      );
    }

    final attentionCount = servers.where((s) => s.status != ServerAdministrativeStatus.active).length;
    final activeCount = servers.length - attentionCount;
    final stoppedCount = servers
        .where((s) => syncState.runtimeFor(s.identifier)?.powerState == ServerPowerState.offline)
        .length;
    final preview = servers.take(4).toList();
    final liveReadings = [
      for (final server in servers)
        if (syncState.runtimeFor(server.identifier) case final reading? when reading.hasResourceReading)
          (server: server, runtime: reading),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xxl),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        _InfrastructureHealthCard(total: servers.length, active: activeCount, stopped: stoppedCount, attention: attentionCount),
        if (liveReadings.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          _ResourceOverviewCard(readings: liveReadings, syncState: syncState, lastSync: _lastObservedAt(syncState)),
        ],
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Expanded(child: Text('Twoje serwery', style: theme.textTheme.titleLarge?.copyWith(color: surfaces.textPrimary))),
            TextButton(
              onPressed: () => context.go(AppRoutes.servers),
              child: const Text('Zobacz wszystkie'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xxs),
        for (var i = 0; i < preview.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: FadeSlideIn(
              index: i,
              child: ServerCard(
                server: preview[i],
                runtimeState: syncState.runtimeFor(preview[i].identifier),
                history: syncState.historyByServer[preview[i].identifier],
                isRefreshing: syncState.isRefreshing(preview[i].identifier),
                hasRecentFailure: syncState.hasRecentFailure(preview[i].identifier),
                onTap: () => context.go(AppRoutes.serverDetail(preview[i].identifier)),
              ),
            ),
          ),
      ],
    );
  }

  DateTime? _lastObservedAt(ServerRuntimeSyncState syncState) {
    DateTime? latest;
    for (final reading in syncState.runtimeByServer.values) {
      final observedAt = reading.observedAt;
      if (observedAt == null) continue;
      if (latest == null || observedAt.isAfter(latest)) latest = observedAt;
    }
    return latest;
  }
}

/// The Dashboard's hero: a health ring (proportion of servers currently
/// active) with the total server count at its center — the single
/// biggest, first-read number on the screen — plus a compact three-row
/// breakdown (active/stopped/needs attention) beside it. Replaces both
/// the old "three equal cards" *and* its own immediate predecessor (a
/// bare number over a row of small stats): the ring gives "how healthy is
/// this, roughly" a shape you register before reading a single digit,
/// which a stack of numbers alone cannot do.
class _InfrastructureHealthCard extends StatelessWidget {
  const _InfrastructureHealthCard({required this.total, required this.active, required this.stopped, required this.attention});

  final int total;
  final int active;
  final int stopped;
  final int attention;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaces = AppSurfaceColors.of(context);
    final semantic = AppSemanticColors.of(context);
    final healthyRatio = total == 0 ? 0.0 : active / total;

    return AppCard(
      elevated: true,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'STAN INFRASTRUKTURY',
            style: theme.textTheme.labelSmall?.copyWith(color: surfaces.textTertiary, letterSpacing: 0.8),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 96,
                height: 96,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: healthyRatio),
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, _) => CircularProgressIndicator(
                        value: value,
                        strokeWidth: 6,
                        strokeCap: StrokeCap.round,
                        backgroundColor: surfaces.surfaceActive,
                        valueColor: AlwaysStoppedAnimation(semantic.success),
                      ),
                    ),
                    // Just the number — no "serwerów" label crammed inside
                    // the ring too (it used to visually collide with the
                    // stroke). The header subtitle right above already
                    // says "X serwerów", and "STAN INFRASTRUKTURY" labels
                    // this whole card, so the bare number reads fine
                    // without repeating the unit a third time.
                    Text(
                      '$total',
                      style: AppTypography.metricNumber.copyWith(fontSize: 30, color: surfaces.textPrimary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  children: [
                    _HealthRow(color: semantic.success, label: 'Aktywne', value: active),
                    const SizedBox(height: AppSpacing.sm),
                    _HealthRow(color: surfaces.textTertiary, label: 'Zatrzymane', value: stopped),
                    const SizedBox(height: AppSpacing.sm),
                    _HealthRow(
                      color: attention > 0 ? semantic.pending : surfaces.textTertiary,
                      label: 'Wymaga uwagi',
                      value: attention,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HealthRow extends StatelessWidget {
  const _HealthRow({required this.color, required this.label, required this.value});

  final Color color;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaces = AppSurfaceColors.of(context);

    return Row(
      children: [
        StatusDot(color: color, size: 7),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(color: surfaces.textSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text('$value', style: AppTypography.metricNumber.copyWith(fontSize: 16, color: surfaces.textPrimary)),
      ],
    );
  }
}

/// Aggregate CPU/RAM/network across every server that has reported a live
/// reading so far, each with a sparkline of real recent samples — shown
/// only once at least one reading exists, never as a zeroed-out
/// placeholder. This is what makes the screen visibly "live", not just
/// a snapshot from whenever it happened to load.
class _ResourceOverviewCard extends StatelessWidget {
  const _ResourceOverviewCard({required this.readings, required this.syncState, required this.lastSync});

  final List<({Server server, ServerRuntimeState runtime})> readings;
  final ServerRuntimeSyncState syncState;
  final DateTime? lastSync;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaces = AppSurfaceColors.of(context);
    final semantic = AppSemanticColors.of(context);

    final avgCpu = readings.map((r) => r.runtime.cpuAbsolutePercent ?? 0).reduce((a, b) => a + b) / readings.length;
    final totalMemory = readings.map((r) => r.runtime.memoryBytes ?? 0).reduce((a, b) => a + b);

    final histories = [for (final r in readings) syncState.historyFor(r.server.identifier)];
    final cpuSeries = _averaged([for (final h in histories) h.cpuSeries]);
    final memorySeries = _summed([for (final h in histories) h.memoryBytesSeries]);
    final networkSeries = _summed([for (final h in histories) h.networkThroughputSeries]);

    final latestSamples = [for (final h in histories) h.latest];
    final measuredRx = latestSamples.where((s) => s?.networkRxRateBytesPerSecond != null);
    final measuredTx = latestSamples.where((s) => s?.networkTxRateBytesPerSecond != null);
    final totalRx = measuredRx.isEmpty
        ? null
        : measuredRx.fold<double>(0, (sum, s) => sum + s!.networkRxRateBytesPerSecond!);
    final totalTx = measuredTx.isEmpty
        ? null
        : measuredTx.fold<double>(0, (sum, s) => sum + s!.networkTxRateBytesPerSecond!);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Wykorzystanie zasobów', style: theme.textTheme.titleSmall?.copyWith(color: surfaces.textPrimary)),
              ),
              if (lastSync != null)
                Text(
                  formatRelativeTime(lastSync!),
                  style: theme.textTheme.labelSmall?.copyWith(color: surfaces.textTertiary),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _ResourceRow(
            label: 'CPU',
            color: semantic.info,
            series: cpuSeries,
            valueWidget: Text(
              '${avgCpu.round()}%',
              style: AppTypography.metricNumber.copyWith(fontSize: 20, color: surfaces.textPrimary),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _ResourceRow(
            label: 'RAM',
            color: semantic.info,
            series: memorySeries,
            valueWidget: Text(
              formatBytesAsMb(totalMemory),
              style: AppTypography.metricNumber.copyWith(fontSize: 20, color: surfaces.textPrimary),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _ResourceRow(
            label: 'SIEĆ',
            color: semantic.info,
            series: networkSeries,
            valueWidget: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _NetworkRateLine(icon: Icons.arrow_upward_rounded, value: formatRate(totalTx)),
                _NetworkRateLine(icon: Icons.arrow_downward_rounded, value: formatRate(totalRx)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<double> _averaged(List<List<double>> series) {
    final aligned = _alignToShortest(series);
    if (aligned.isEmpty) return const [];
    final length = aligned.first.length;
    return [for (var i = 0; i < length; i++) aligned.map((s) => s[i]).reduce((a, b) => a + b) / aligned.length];
  }

  List<double> _summed(List<List<double>> series) {
    final aligned = _alignToShortest(series);
    if (aligned.isEmpty) return const [];
    final length = aligned.first.length;
    return [for (var i = 0; i < length; i++) aligned.map((s) => s[i]).reduce((a, b) => a + b)];
  }

  /// Right-aligns every server's series to the shortest one among them —
  /// servers that joined polling later (or just had a fetch fail once)
  /// otherwise cannot be summed/averaged index-for-index against ones
  /// with a longer history.
  List<List<double>> _alignToShortest(List<List<double>> series) {
    final nonEmpty = series.where((s) => s.isNotEmpty).toList();
    if (nonEmpty.isEmpty) return const [];
    final minLength = nonEmpty.map((s) => s.length).reduce(math.min);
    return [for (final s in nonEmpty) s.sublist(s.length - minLength)];
  }
}

class _NetworkRateLine extends StatelessWidget {
  const _NetworkRateLine({required this.icon, required this.value});

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
        Text(value, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: surfaces.textPrimary)),
      ],
    );
  }
}

class _ResourceRow extends StatelessWidget {
  const _ResourceRow({required this.label, required this.color, required this.series, required this.valueWidget});

  final String label;
  final Color color;
  final List<double> series;
  final Widget valueWidget;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaces = AppSurfaceColors.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 84,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: theme.textTheme.labelSmall?.copyWith(color: surfaces.textTertiary, letterSpacing: 0.6)),
              const SizedBox(height: 2),
              // `FittedBox`, not a fixed style: [valueWidget] renders real
              // formatted numbers (bytes, rates) of unpredictable width —
              // this scales the rare too-wide value down to fit this
              // column instead of overflowing it.
              FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: valueWidget),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Sparkline(values: series, color: color, height: 32)),
      ],
    );
  }
}

class _NoServersYet extends StatelessWidget {
  const _NoServersYet();

  @override
  Widget build(BuildContext context) {
    final surfaces = AppSurfaceColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.dns_outlined, size: 48, color: surfaces.textTertiary),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'To konto nie ma jeszcze dostępu do żadnego serwera na tym panelu.',
              textAlign: TextAlign.center,
              style: TextStyle(color: surfaces.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SkeletonBox(height: 172, borderRadius: BorderRadius.circular(AppRadius.md)),
        const SizedBox(height: AppSpacing.sm),
        SkeletonBox(height: 156, borderRadius: BorderRadius.circular(AppRadius.md)),
        const SizedBox(height: AppSpacing.lg),
        const SkeletonBox(width: 140, height: 20),
        const SizedBox(height: AppSpacing.sm),
        for (var i = 0; i < 3; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: SkeletonBox(height: 132, borderRadius: BorderRadius.circular(AppRadius.md)),
          ),
      ],
    );
  }
}
