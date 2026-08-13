import 'package:flutter/material.dart';

import '../../../../core/presentation/widgets/app_status_badge.dart';
import '../../../../core/theme/app_status_tokens.dart';
import '../../domain/server_power_state.dart';

/// Badge showing a server's *live* power state (from Wings, via
/// [ServerRuntimeState]) — **not** its administrative status, which is
/// [ServerStatusChip] instead. A server can be administratively
/// [ServerAdministrativeStatus.active] and still show [ServerPowerState.offline]
/// here (allowed to run, but the process just isn't up right now).
class PowerStateChip extends StatelessWidget {
  const PowerStateChip({super.key, required this.state, this.dense = false});

  final ServerPowerState state;
  final bool dense;

  @override
  Widget build(BuildContext context) => AppStatusBadge(visual: _visualFor(state), dense: dense);

  static AppStatusVisual _visualFor(ServerPowerState state) {
    return switch (state) {
      ServerPowerState.running =>
        const AppStatusVisual(icon: Icons.play_circle_outline, label: 'Uruchomiony', tone: AppStatusTone.success),
      ServerPowerState.starting => const AppStatusVisual(
          icon: Icons.hourglass_top,
          label: 'Uruchamianie…',
          tone: AppStatusTone.pending,
          isAnimated: true,
        ),
      ServerPowerState.stopping => const AppStatusVisual(
          icon: Icons.hourglass_bottom,
          label: 'Zatrzymywanie…',
          tone: AppStatusTone.pending,
          isAnimated: true,
        ),
      ServerPowerState.offline =>
        const AppStatusVisual(icon: Icons.stop_circle_outlined, label: 'Zatrzymany', tone: AppStatusTone.neutral),
      ServerPowerState.unknown =>
        const AppStatusVisual(icon: Icons.help_outline, label: 'Nieznany', tone: AppStatusTone.neutral),
    };
  }
}
