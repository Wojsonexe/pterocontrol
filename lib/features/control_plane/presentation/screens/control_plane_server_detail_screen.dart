import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/app_exception.dart';
import '../../../../core/presentation/widgets/app_card.dart';
import '../../../../core/presentation/widgets/app_top_bar.dart';
import '../../../../core/presentation/widgets/error_view.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../application/control_plane_server_detail_providers.dart';
import '../../domain/control_plane_power_action.dart';
import '../../domain/control_plane_resource_usage.dart';

/// Live resources + power control for one server, via the Control Plane
/// backend rather than a direct Pterodactyl connection — see
/// IMPLEMENTATION_STATUS.md, "Zakres pierwszego, wąskiego MVP-slice'a" for
/// why this MVP slice stops here (no console/files/backups/schedules yet).
class ControlPlaneServerDetailScreen extends ConsumerWidget {
  const ControlPlaneServerDetailScreen({super.key, required this.serverId});

  final String serverId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resourcesAsync = ref.watch(controlPlaneResourcesProvider(serverId));

    return Scaffold(
      appBar: const AppTopBar(title: 'Serwer'),
      body: resourcesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => ErrorView(
          message: error is AppException ? error.message : 'Nie udało się wczytać zasobów serwera.',
          onRetry: () => ref.invalidate(controlPlaneResourcesProvider(serverId)),
        ),
        data: (usage) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(controlPlaneResourcesProvider(serverId)),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              _ResourcesCard(usage: usage),
              const SizedBox(height: AppSpacing.md),
              _PowerActionsCard(serverId: serverId),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResourcesCard extends StatelessWidget {
  const _ResourcesCard({required this.usage});

  final ControlPlaneResourceUsage usage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Zasoby', style: theme.textTheme.titleMedium),
              const Spacer(),
              Chip(
                label: Text(usage.currentState),
                visualDensity: VisualDensity.compact,
              ),
              if (usage.isSuspended) ...[
                const SizedBox(width: AppSpacing.xs),
                const Chip(label: Text('Zawieszony'), visualDensity: VisualDensity.compact),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _MetricRow(label: 'CPU', value: '${usage.cpuAbsolutePercent.toStringAsFixed(1)}%'),
          _MetricRow(label: 'Pamięć', value: _formatBytes(usage.memoryBytes)),
          _MetricRow(label: 'Dysk', value: _formatBytes(usage.diskBytes)),
          _MetricRow(label: 'Sieć ↓/↑', value: '${_formatBytes(usage.networkRxBytes)} / ${_formatBytes(usage.networkTxBytes)}'),
          _MetricRow(label: 'Czas działania', value: _formatUptime(usage.uptimeMs)),
        ],
      ),
    );
  }

  static String _formatBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex++;
    }
    return '${value.toStringAsFixed(value >= 10 || unitIndex == 0 ? 0 : 1)} ${units[unitIndex]}';
  }

  static String _formatUptime(int uptimeMs) {
    final duration = Duration(milliseconds: uptimeMs);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m';
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          Text(value, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _PowerActionsCard extends ConsumerWidget {
  const _PowerActionsCard({required this.serverId});

  final String serverId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final actionState = ref.watch(controlPlanePowerActionControllerProvider(serverId));
    final isSending = actionState.isLoading;

    ref.listen(controlPlanePowerActionControllerProvider(serverId), (previous, next) {
      final error = next.hasError ? next.error : null;
      if (error != null) {
        final message = error is AppException ? error.message : 'Nie udało się wysłać polecenia.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    });

    void send(ControlPlanePowerAction action) {
      ref.read(controlPlanePowerActionControllerProvider(serverId).notifier).send(action);
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Zasilanie', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Polecenie zostanie wysłane, ale nie oznacza natychmiastowej zmiany stanu — odśwież zasoby, aby zobaczyć wynik.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              OutlinedButton.icon(
                onPressed: isSending ? null : () => send(ControlPlanePowerAction.start),
                icon: const Icon(Icons.play_arrow_outlined),
                label: const Text('Start'),
              ),
              OutlinedButton.icon(
                onPressed: isSending ? null : () => send(ControlPlanePowerAction.restart),
                icon: const Icon(Icons.refresh_outlined),
                label: const Text('Restart'),
              ),
              OutlinedButton.icon(
                onPressed: isSending ? null : () => send(ControlPlanePowerAction.stop),
                icon: const Icon(Icons.stop_outlined),
                label: const Text('Stop'),
              ),
              OutlinedButton.icon(
                onPressed: isSending ? null : () => send(ControlPlanePowerAction.kill),
                icon: Icon(Icons.power_settings_new, color: theme.colorScheme.error),
                label: Text('Kill', style: TextStyle(color: theme.colorScheme.error)),
              ),
            ],
          ),
          if (isSending) ...[
            const SizedBox(height: AppSpacing.sm),
            const LinearProgressIndicator(),
          ],
        ],
      ),
    );
  }
}
