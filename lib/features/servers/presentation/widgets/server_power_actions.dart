import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/app_exception.dart';
import '../../../../core/theme/app_semantic_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../application/server_power_action_controller.dart';
import '../../domain/server.dart';
import '../../domain/server_power_action.dart';

/// Start/Restart/Stop/Kill controls for one server.
///
/// Fire-and-forget by design, matching the Pterodactyl Client API — see
/// `ServerPowerAction`'s doc comment. Success/error feedback is shown as a
/// `SnackBar` via `ref.listen`, the same pattern already used by
/// `AddInstanceScreen`/`InstancesScreen`.
class ServerPowerActions extends ConsumerWidget {
  const ServerPowerActions({super.key, required this.instanceId, required this.server});

  final String instanceId;
  final Server server;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final target = (instanceId: instanceId, serverIdentifier: server.identifier);
    final actionState = ref.watch(serverPowerActionControllerProvider(target));
    final notifier = ref.read(serverPowerActionControllerProvider(target).notifier);

    ref.listen<AsyncValue<ServerPowerAction?>>(serverPowerActionControllerProvider(target), (previous, next) {
      final error = next.error;
      if (error != null && !next.isLoading) {
        final message = error is AppException ? error.message : 'Nie udało się wykonać akcji.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
        return;
      }

      final wasLoading = previous?.isLoading ?? false;
      final completedAction = next.value;
      if (wasLoading && next.hasValue && completedAction != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Wysłano polecenie: ${_labelFor(completedAction)}')),
        );
      }
    });

    final isBusy = actionState.isLoading;
    final canControlPower = server.status == ServerAdministrativeStatus.active;
    final theme = Theme.of(context);
    final danger = AppSemanticColors.of(context).danger;

    Future<void> handle(ServerPowerAction action) async {
      if (action == ServerPowerAction.kill) {
        final confirmed = await _confirmKill(context);
        if (confirmed != true) return;
      }
      await notifier.send(action);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Sterowanie serwerem', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.xxs),
        if (!canControlPower)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Text(
              'Niedostępne, gdy serwer jest zawieszony albo w trakcie instalacji/przywracania backupu.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        if (isBusy)
          const Padding(
            padding: EdgeInsets.only(bottom: AppSpacing.xs),
            child: LinearProgressIndicator(semanticsLabel: 'Wykonywanie akcji'),
          ),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            FilledButton.icon(
              onPressed: (isBusy || !canControlPower) ? null : () => handle(ServerPowerAction.start),
              icon: const Icon(Icons.play_arrow_outlined),
              label: const Text('Start'),
            ),
            OutlinedButton.icon(
              onPressed: (isBusy || !canControlPower) ? null : () => handle(ServerPowerAction.restart),
              icon: const Icon(Icons.refresh_outlined),
              label: const Text('Restart'),
            ),
            OutlinedButton.icon(
              onPressed: (isBusy || !canControlPower) ? null : () => handle(ServerPowerAction.stop),
              icon: const Icon(Icons.stop_outlined),
              label: const Text('Stop'),
            ),
          ],
        ),
        // Kill is deliberately separated from the constructive actions
        // above — a divider + full-width button, not just "whatever
        // happened to wrap to the next line" — so the destructive action
        // reads as its own clearly-bounded zone, matching the "danger
        // zone" pattern common in production apps/settings screens.
        const SizedBox(height: AppSpacing.sm),
        Divider(height: 1, color: theme.colorScheme.outlineVariant),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: danger,
              side: BorderSide(color: danger),
            ),
            onPressed: (isBusy || !canControlPower) ? null : () => handle(ServerPowerAction.kill),
            icon: const Icon(Icons.power_settings_new_outlined),
            label: const Text('Kill'),
          ),
        ),
      ],
    );
  }

  Future<bool?> _confirmKill(BuildContext context) {
    final danger = AppSemanticColors.of(context).danger;
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Wymusić zatrzymanie serwera?'),
        content: const Text(
          'Kill natychmiast przerywa proces serwera, bez bezpiecznego zapisu. '
          'Użyj tylko wtedy, gdy Stop nie działa — możliwa utrata niezapisanych danych.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Anuluj')),
          FilledButton.tonal(
            style: FilledButton.styleFrom(foregroundColor: danger),
            autofocus: false,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Wymuś Kill'),
          ),
        ],
      ),
    );
  }

  String _labelFor(ServerPowerAction action) => switch (action) {
        ServerPowerAction.start => 'Start',
        ServerPowerAction.restart => 'Restart',
        ServerPowerAction.stop => 'Stop',
        ServerPowerAction.kill => 'Kill',
      };
}
