import 'package:meta/meta.dart';

/// Live resource usage for one server, as returned by
/// `GET /servers/:id/resources` — a direct pass-through of
/// `PterodactylResourceUsageDto` from `services/control-plane-api`.
@immutable
class ControlPlaneResourceUsage {
  const ControlPlaneResourceUsage({
    required this.currentState,
    required this.isSuspended,
    required this.cpuAbsolutePercent,
    required this.memoryBytes,
    required this.diskBytes,
    required this.networkRxBytes,
    required this.networkTxBytes,
    required this.uptimeMs,
  });

  final String currentState;
  final bool isSuspended;
  final double cpuAbsolutePercent;
  final int memoryBytes;
  final int diskBytes;
  final int networkRxBytes;
  final int networkTxBytes;
  final int uptimeMs;
}
