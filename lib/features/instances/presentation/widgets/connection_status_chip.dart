import 'package:flutter/material.dart';

import '../../../../core/presentation/widgets/app_status_badge.dart';
import '../../../../core/theme/app_status_tokens.dart';
import '../../domain/pterodactyl_instance.dart';

/// Small badge showing an instance's last known [InstanceConnectionStatus].
///
/// A thin wrapper over the shared [AppStatusBadge] — this class exists so
/// call sites keep saying `ConnectionStatusChip(status: ...)` (nothing
/// about the instances feature needs to know [AppStatusVisual] exists),
/// while the actual badge rendering lives in exactly one place shared
/// with `ServerStatusChip` and the console's connection indicator.
class ConnectionStatusChip extends StatelessWidget {
  const ConnectionStatusChip({super.key, required this.status, this.dense = false});

  final InstanceConnectionStatus status;
  final bool dense;

  @override
  Widget build(BuildContext context) => AppStatusBadge(visual: _visualFor(status), dense: dense);

  static AppStatusVisual _visualFor(InstanceConnectionStatus status) {
    return switch (status) {
      InstanceConnectionStatus.online =>
        const AppStatusVisual(icon: Icons.check_circle, label: 'Online', tone: AppStatusTone.success),
      InstanceConnectionStatus.offline =>
        const AppStatusVisual(icon: Icons.cancel, label: 'Offline', tone: AppStatusTone.danger),
      InstanceConnectionStatus.checking => const AppStatusVisual(
          icon: Icons.sync,
          label: 'Sprawdzanie…',
          tone: AppStatusTone.pending,
          isAnimated: true,
        ),
      InstanceConnectionStatus.error =>
        const AppStatusVisual(icon: Icons.error, label: 'Błąd autoryzacji', tone: AppStatusTone.danger),
      InstanceConnectionStatus.unknown =>
        const AppStatusVisual(icon: Icons.help_outline, label: 'Nieznany', tone: AppStatusTone.neutral),
    };
  }
}
