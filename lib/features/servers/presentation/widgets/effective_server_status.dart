import 'package:flutter/material.dart';

import '../../../../core/theme/app_status_tokens.dart';
import '../../domain/server.dart';
import '../../domain/server_power_state.dart';

/// Collapses a server's administrative status (Panel) and live power
/// state (Wings, once known) into exactly **one** [AppStatusVisual] —
/// what [ServerCard] shows as its single primary badge.
///
/// `ServerStatusChip`/`PowerStateChip` still exist and still show the two
/// facts *separately* where a screen has room and reason to (the detail
/// screen's Overview tab shows both) — but a compact card showing two
/// badges side by side reads as uncertain ("is it this or that?"), not as
/// a confident, premium status readout. This is the single source of
/// truth for "what should the badge say" so that priority order (a
/// suspended/failed server always wins over a stale power reading, an
/// in-progress install always wins over "unknown") is decided in exactly
/// one place.
AppStatusVisual effectiveServerStatus({
  required ServerAdministrativeStatus administrativeStatus,
  required ServerPowerState? powerState,
}) {
  return switch (administrativeStatus) {
    ServerAdministrativeStatus.suspended =>
      const AppStatusVisual(icon: Icons.block_rounded, label: 'Zawieszony', tone: AppStatusTone.danger),
    ServerAdministrativeStatus.installFailed ||
    ServerAdministrativeStatus.reinstallFailed =>
      const AppStatusVisual(icon: Icons.error_rounded, label: 'Błąd', tone: AppStatusTone.danger),
    ServerAdministrativeStatus.installing => const AppStatusVisual(
        icon: Icons.download_rounded,
        label: 'Instalacja',
        tone: AppStatusTone.pending,
        isAnimated: true,
      ),
    ServerAdministrativeStatus.restoringBackup => const AppStatusVisual(
        icon: Icons.settings_backup_restore_rounded,
        label: 'Przywracanie',
        tone: AppStatusTone.pending,
        isAnimated: true,
      ),
    ServerAdministrativeStatus.unknown =>
      const AppStatusVisual(icon: Icons.help_rounded, label: 'Nieznany', tone: AppStatusTone.neutral),
    ServerAdministrativeStatus.active => switch (powerState) {
        null || ServerPowerState.unknown || ServerPowerState.running =>
          const AppStatusVisual(icon: Icons.circle, label: 'Aktywny', tone: AppStatusTone.success),
        ServerPowerState.starting => const AppStatusVisual(
            icon: Icons.arrow_upward_rounded,
            label: 'Uruchamianie',
            tone: AppStatusTone.pending,
            isAnimated: true,
          ),
        ServerPowerState.stopping => const AppStatusVisual(
            icon: Icons.arrow_downward_rounded,
            label: 'Zatrzymywanie',
            tone: AppStatusTone.pending,
            isAnimated: true,
          ),
        ServerPowerState.offline =>
          const AppStatusVisual(icon: Icons.stop_circle_rounded, label: 'Zatrzymany', tone: AppStatusTone.neutral),
      },
  };
}
