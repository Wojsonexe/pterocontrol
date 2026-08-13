import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/app_exception.dart';
import '../../../../core/formatting/metric_formatting.dart';
import '../../../../core/presentation/widgets/app_card.dart';
import '../../../../core/presentation/widgets/app_status_badge.dart';
import '../../../../core/presentation/widgets/app_top_bar.dart';
import '../../../../core/presentation/widgets/coming_soon_view.dart';
import '../../../../core/presentation/widgets/error_view.dart';
import '../../../../core/presentation/widgets/metric_grid.dart';
import '../../../../core/presentation/widgets/section_header.dart';
import '../../../../core/presentation/widgets/sparkline.dart';
import '../../../../core/presentation/widgets/status_dot.dart';
import '../../../../core/presentation/widgets/usage_bar.dart';
import '../../../../core/theme/app_semantic_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_surface_colors.dart';
import '../../../console/application/console_controller.dart';
import '../../../console/data/console_protocol_events.dart';
import '../../../console/domain/console_event.dart';
import '../../../console/presentation/widgets/console_view.dart';
import '../../../instances/application/instance_list_controller.dart';
import '../../application/server_list_controller.dart';
import '../../application/server_runtime_sync_controller.dart';
import '../../domain/server.dart';
import '../../domain/server_power_state.dart';
import '../../domain/server_runtime_state.dart';
import '../widgets/effective_server_status.dart';
import '../widgets/power_state_chip.dart';
import '../widgets/server_power_actions.dart';
import '../widgets/server_status_chip.dart';

/// Wings event names that mean "the server's administrative status just
/// changed and the cached [Server] this screen is showing is now stale" —
/// see [_ServerDetailContentState._handleConsoleEvents].
const _statusInvalidatingEvents = {
  ConsoleProtocolEvent.installCompleted,
  ConsoleProtocolEvent.backupRestoreCompleted,
};

/// Detail screen for a single server — the hub for everything scoped to
/// that server: overview, console, files, backups, per-server settings.
///
/// Deliberately reads the server out of `serverListControllerProvider`'s
/// already-loaded list (by [serverId]) rather than issuing a dedicated
/// `GET /api/client/servers/{server}` call — see the field-by-field
/// rationale this always had. The active instance is resolved internally
/// (not a constructor parameter) because, in the `/app` shell, "which
/// instance" is always "the active one" — see `RootScreen`.
///
/// Files/Backups/per-server Startup+Environment settings have their own
/// tabs here (matching the information architecture a real Pterodactyl
/// client needs) but show [ComingSoonView] — this app has no REST
/// integration for those endpoints yet (see README); the tabs exist so
/// the navigation shape is right, not to fake functionality that isn't
/// there.
class ServerDetailScreen extends ConsumerWidget {
  const ServerDetailScreen({super.key, required this.serverId});

  final String serverId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final instanceId = ref.watch(instanceListControllerProvider).value?.activeInstanceId;
    if (instanceId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Serwer')),
        body: const Center(child: Text('Brak aktywnego panelu.')),
      );
    }

    final state = ref.watch(serverListControllerProvider(instanceId));

    return state.when(
      data: (data) {
        Server? server;
        for (final candidate in data.servers) {
          if (candidate.identifier == serverId) {
            server = candidate;
            break;
          }
        }

        if (server == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Serwer')),
            body: const Center(child: Text('Nie znaleziono serwera na tej instancji.')),
          );
        }

        return _ServerDetailContent(instanceId: instanceId, server: server);
      },
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, stackTrace) => Scaffold(
        appBar: AppBar(title: const Text('Serwer')),
        body: ErrorView(
          message: error is AppException ? error.message : 'Nie udało się wczytać serwera.',
        ),
      ),
    );
  }
}

/// Hosts the tab scaffold, and — regardless of which tab is open — keeps
/// this screen's cached [Server] in sync with two Wings WebSocket events
/// that mean the Panel's *administrative* status of this server just
/// changed: `install completed` (a fresh install, or a reinstall, just
/// finished — status flips out of `installing`) and
/// `backup restore completed` (status flips out of `restoringBackup`).
/// `.../resources` (what `ServerRuntimeSyncController` polls) cannot see
/// this transition itself — it only ever reports Wings' live power state,
/// never the Panel's administrative one — so without this, a server stuck
/// on "Instalacja..." would only clear once the user left and re-entered
/// this screen. [ConsoleController] is already connected here (`ConsoleView`
/// is one of this screen's tabs, built eagerly by `TabBarView` regardless
/// of which tab is selected) — this only *observes* its event buffer, it
/// does not open a second connection.
class _ServerDetailContent extends ConsumerStatefulWidget {
  const _ServerDetailContent({required this.instanceId, required this.server});

  final String instanceId;
  final Server server;

  @override
  ConsumerState<_ServerDetailContent> createState() => _ServerDetailContentState();
}

class _ServerDetailContentState extends ConsumerState<_ServerDetailContent> {
  int _lastEventCount = 0;

  void _handleConsoleEvents(List<ConsoleEvent> events) {
    if (events.length <= _lastEventCount) {
      // Buffer shrank/reset (a genuine WS reconnect clears it) rather than
      // grew — nothing new to diff. If a status-changing event happened to
      // arrive in the same instant as a reconnect, `ServerRuntimeSyncController`'s
      // next poll tick still catches it — this is a fast path, not the
      // only path.
      _lastEventCount = events.length;
      return;
    }
    final newEvents = events.sublist(_lastEventCount);
    _lastEventCount = events.length;

    final invalidated = newEvents.any(
      (e) => e.type == ConsoleEventType.unknown && _statusInvalidatingEvents.contains(e.message),
    );
    if (invalidated) {
      unawaited(
        ref.read(serverListControllerProvider(widget.instanceId).notifier).refreshOne(widget.server.identifier),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final instanceId = widget.instanceId;
    final server = widget.server;
    final target = (instanceId: instanceId, serverIdentifier: server.identifier);

    ref.listen(consoleControllerProvider(target), (previous, next) {
      final events = next.value?.events;
      if (events != null) _handleConsoleEvents(events);
    });

    final runtimeState = ref.watch(consoleControllerProvider(target)).value?.runtimeState;
    final visual = effectiveServerStatus(administrativeStatus: server.status, powerState: runtimeState?.powerState);

    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppTopBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: 'Wstecz',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          title: server.name,
          subtitle: server.node,
          trailing: AppStatusBadge(visual: visual, dense: true),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Podsumowanie'),
              Tab(text: 'Konsola'),
              Tab(text: 'Pliki'),
              Tab(text: 'Backupy'),
              Tab(text: 'Ustawienia'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _OverviewTab(instanceId: instanceId, server: server),
            ConsoleView(instanceId: instanceId, serverIdentifier: server.identifier, fullscreen: true),
            const _FilesTab(),
            const _BackupsTab(),
            _ServerSettingsTab(server: server),
          ],
        ),
      ),
    );
  }
}

class _OverviewTab extends ConsumerWidget {
  const _OverviewTab({required this.instanceId, required this.server});

  final String instanceId;
  final Server server;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final surfaces = AppSurfaceColors.of(context);
    final semantic = AppSemanticColors.of(context);
    final target = (instanceId: instanceId, serverIdentifier: server.identifier);
    final runtimeState = ref.watch(consoleControllerProvider(target)).value?.runtimeState;
    final hasLiveReading = runtimeState != null && runtimeState.hasResourceReading;
    // The same real, bounded sample history `ServerRuntimeSyncController`
    // already accumulates for the Dashboard's sparklines — reused here,
    // not a second history mechanism. Only ever real observed readings;
    // see `ServerMetricsHistory`'s own doc comment.
    final history = ref.watch(serverRuntimeSyncControllerProvider(instanceId)).historyFor(server.identifier);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        AppCard(
          elevated: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ServerStatusChip(status: server.status),
                  if (hasLiveReading) ...[
                    const SizedBox(width: AppSpacing.xs),
                    PowerStateChip(state: runtimeState.powerState),
                    const SizedBox(width: AppSpacing.xxs),
                    StatusDot(
                      color: runtimeState.powerState == ServerPowerState.running ? semantic.success : semantic.neutral,
                      pulsing: runtimeState.powerState == ServerPowerState.running,
                    ),
                  ],
                ],
              ),
              if (server.isTransferring) ...[
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Icon(Icons.sync_alt_rounded, size: 16, color: semantic.pending),
                    const SizedBox(width: AppSpacing.xxs),
                    Text(
                      "Serwer jest w trakcie transferu między node'ami",
                      style: theme.textTheme.bodySmall?.copyWith(color: surfaces.textSecondary),
                    ),
                  ],
                ),
              ],
              if (server.description != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(server.description!, style: theme.textTheme.bodyMedium?.copyWith(color: surfaces.textSecondary)),
              ],
              if (hasLiveReading && runtimeState.uptimeMs != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Icon(Icons.timer_outlined, size: 14, color: surfaces.textTertiary),
                    const SizedBox(width: AppSpacing.xxs),
                    Text(
                      'Działa od ${formatUptime(runtimeState.uptimeMs!)}',
                      style: theme.textTheme.labelSmall?.copyWith(color: surfaces.textTertiary),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        if (hasLiveReading) ...[
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader('Na żywo'),
          const SizedBox(height: AppSpacing.sm),
          AppCard(
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: UsageBar(
                        label: 'CPU',
                        valueLabel: '${runtimeState.cpuAbsolutePercent!.round()}%',
                        ratio: runtimeState.cpuAbsolutePercent! /
                            (server.limits.cpuPercent > 0 ? server.limits.cpuPercent : 100),
                        color: semantic.info,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(
                      child: UsageBar(
                        label: 'RAM',
                        valueLabel: formatBytesAsMb(runtimeState.memoryBytes ?? 0),
                        ratio: server.limits.memoryMb > 0
                            ? (runtimeState.memoryBytes ?? 0) / (server.limits.memoryMb * 1024 * 1024)
                            : 0,
                        color: semantic.info,
                      ),
                    ),
                  ],
                ),
                if (history.samples.length > 1) ...[
                  const SizedBox(height: AppSpacing.md),
                  Divider(height: 1, color: surfaces.border),
                  const SizedBox(height: AppSpacing.md),
                  _TrendRow(label: 'CPU', color: semantic.info, series: history.cpuSeries),
                  const SizedBox(height: AppSpacing.sm),
                  _TrendRow(
                    label: 'RAM',
                    color: semantic.info,
                    series: [for (final b in history.memoryBytesSeries) b / (1024 * 1024)],
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                MetricGrid(items: _liveExtraMetricsFor(runtimeState)),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        const SectionHeader('Informacje'),
        const SizedBox(height: AppSpacing.sm),
        AppCard(child: MetricGrid(items: _metricsFor(server))),
        const SizedBox(height: AppSpacing.lg),
        const SectionHeader('Sterowanie'),
        const SizedBox(height: AppSpacing.sm),
        AppCard(child: ServerPowerActions(instanceId: instanceId, server: server)),
      ],
    );
  }

  List<MetricItem> _metricsFor(Server server) => [
        MetricItem(icon: Icons.dns_outlined, label: 'Node', value: server.node),
        MetricItem(icon: Icons.memory_outlined, label: 'Pamięć RAM', value: '${server.limits.memoryMb} MB'),
        MetricItem(icon: Icons.storage_outlined, label: 'Dysk', value: '${server.limits.diskMb} MB'),
        MetricItem(
          icon: Icons.speed_outlined,
          label: 'CPU',
          value: server.limits.cpuPercent == 0 ? 'Bez limitu' : '${server.limits.cpuPercent}%',
        ),
      ];

  /// Rows below the CPU/RAM [UsageBar]s in the "Na żywo" card —
  /// [runtimeState] is only ever passed here when
  /// [ServerRuntimeState.hasResourceReading] is already true.
  List<MetricItem> _liveExtraMetricsFor(ServerRuntimeState runtimeState) => [
        MetricItem(
          icon: Icons.storage_outlined,
          label: 'Dysk',
          value: formatBytesAsMb(runtimeState.diskBytes ?? 0),
        ),
        MetricItem(
          icon: Icons.swap_vert,
          label: 'Sieć (odbiór/wysyłka)',
          value: '${formatBytesAsMb(runtimeState.networkRxBytes ?? 0)} / ${formatBytesAsMb(runtimeState.networkTxBytes ?? 0)}',
        ),
      ];
}

/// A short trend line for one metric, matching the exact visual
/// convention the Dashboard's resource-overview card already uses
/// (`_ResourceRow`) — label in a fixed-width column, [Sparkline] filling
/// the rest — so a server's detail screen and the Dashboard read as the
/// same product, not two different ones bolted together.
class _TrendRow extends StatelessWidget {
  const _TrendRow({required this.label, required this.color, required this.series});

  final String label;
  final Color color;
  final List<double> series;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaces = AppSurfaceColors.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 40,
          child: Text(label, style: theme.textTheme.labelSmall?.copyWith(color: surfaces.textTertiary, letterSpacing: 0.6)),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Sparkline(values: series, color: color, height: 24)),
      ],
    );
  }
}

class _FilesTab extends StatelessWidget {
  const _FilesTab();

  @override
  Widget build(BuildContext context) {
    return const ComingSoonView(
      icon: Icons.folder_outlined,
      title: 'Menedżer plików',
      message: 'Przeglądanie, edycja i przesyłanie plików serwera pojawi się w kolejnej aktualizacji.',
    );
  }
}

class _BackupsTab extends StatelessWidget {
  const _BackupsTab();

  @override
  Widget build(BuildContext context) {
    return const ComingSoonView(
      icon: Icons.backup_outlined,
      title: 'Kopie zapasowe',
      message: 'Tworzenie, pobieranie i przywracanie kopii zapasowych pojawi się w kolejnej aktualizacji.',
    );
  }
}

class _ServerSettingsTab extends StatelessWidget {
  const _ServerSettingsTab({required this.server});

  final Server server;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        const SectionHeader('Ogólne'),
        const SizedBox(height: AppSpacing.sm),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              ListTile(leading: const Icon(Icons.badge_outlined), title: const Text('Identyfikator'), subtitle: Text(server.identifier)),
              ListTile(leading: const Icon(Icons.dns_outlined), title: const Text('Node'), subtitle: Text(server.node)),
              if (server.description != null)
                ListTile(
                  leading: const Icon(Icons.notes_outlined),
                  title: const Text('Opis'),
                  subtitle: Text(server.description!),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Poniższe sekcje będą edytowalne w kolejnej aktualizacji — na razie pokazują, gdzie się pojawią.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.sm),
        const _SettingsSectionPlaceholder(icon: Icons.terminal_outlined, title: 'Startup'),
        const SizedBox(height: AppSpacing.sm),
        const _SettingsSectionPlaceholder(icon: Icons.tune_outlined, title: 'Zmienne środowiskowe'),
      ],
    );
  }
}

class _SettingsSectionPlaceholder extends StatelessWidget {
  const _SettingsSectionPlaceholder({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final surfaces = AppSurfaceColors.of(context);
    return AppCard(
      padding: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(icon, color: surfaces.textTertiary),
        title: Text(title),
        subtitle: const Text('Wkrótce'),
        enabled: false,
      ),
    );
  }
}
