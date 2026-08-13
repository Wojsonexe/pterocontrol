import 'package:flutter/material.dart';

import '../../../../core/presentation/widgets/app_status_badge.dart';
import '../../../../core/theme/app_status_tokens.dart';
import '../../domain/server.dart';

/// Badge showing a server's administrative status (installing, suspended,
/// ...) — **not** its live power state, which comes from the console
/// WebSocket (`ServerRuntimeState`) instead.
///
/// A thin wrapper over the shared [AppStatusBadge] — see
/// `ConnectionStatusChip`'s doc comment for why.
class ServerStatusChip extends StatelessWidget {
  const ServerStatusChip({super.key, required this.status, this.dense = false});

  final ServerAdministrativeStatus status;
  final bool dense;

  @override
  Widget build(BuildContext context) => AppStatusBadge(visual: _visualFor(status), dense: dense);

  static AppStatusVisual _visualFor(ServerAdministrativeStatus status) {
    return switch (status) {
      ServerAdministrativeStatus.active =>
        const AppStatusVisual(icon: Icons.check_circle, label: 'Aktywny', tone: AppStatusTone.success),
      ServerAdministrativeStatus.installing => const AppStatusVisual(
          icon: Icons.sync,
          label: 'Instalacja…',
          tone: AppStatusTone.pending,
          isAnimated: true,
        ),
      ServerAdministrativeStatus.installFailed =>
        const AppStatusVisual(icon: Icons.error, label: 'Instalacja nieudana', tone: AppStatusTone.danger),
      ServerAdministrativeStatus.reinstallFailed =>
        const AppStatusVisual(icon: Icons.error, label: 'Reinstalacja nieudana', tone: AppStatusTone.danger),
      ServerAdministrativeStatus.suspended =>
        const AppStatusVisual(icon: Icons.block, label: 'Zawieszony', tone: AppStatusTone.danger),
      ServerAdministrativeStatus.restoringBackup => const AppStatusVisual(
          icon: Icons.settings_backup_restore,
          label: 'Przywracanie backupu…',
          tone: AppStatusTone.pending,
          isAnimated: true,
        ),
      ServerAdministrativeStatus.unknown =>
        const AppStatusVisual(icon: Icons.help_outline, label: 'Nieznany', tone: AppStatusTone.neutral),
    };
  }
}
