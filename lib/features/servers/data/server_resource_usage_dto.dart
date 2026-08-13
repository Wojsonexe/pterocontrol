/// Raw shape of `GET /api/client/servers/{server}/resources`' `attributes`.
///
/// Verified against the actual Panel/Wings source (not guessed):
/// `Pterodactyl\Transformers\Api\Client\StatsTransformer::transform()`
/// produces `{"current_state", "is_suspended", "resources": {"memory_bytes",
/// "cpu_absolute", "disk_bytes", "network_rx_bytes", "network_tx_bytes",
/// "uptime"}}` — reading straight from Wings' `ResourceUsage` struct
/// (`wings/server/resources.go` embedding `environment.Stats`), the exact
/// same struct Wings also marshals for the WebSocket `stats` event (see
/// `ConsoleRepositoryImpl._handleStats`). This endpoint is deliberately
/// cached server-side for ~20s
/// (`ResourceUtilizationController::__invoke`, `Carbon::now()->addSeconds(20)`,
/// "to ensure that repeated requests to this endpoint do not cause a flood
/// of unnecessary API calls") — polling it faster than that would only
/// ever re-read the same cached value, which is why
/// `ServerRuntimeSyncController` polls at that same cadence, matching
/// exactly what Pterodactyl's own web dashboard does
/// (`resources/scripts/components/dashboard/ServerRow.tsx`:
/// `setInterval(() => getStats(), 30000)`).
class ServerResourceUsageDto {
  const ServerResourceUsageDto({
    required this.currentState,
    required this.isSuspended,
    required this.cpuAbsolutePercent,
    required this.memoryBytes,
    required this.diskBytes,
    required this.networkRxBytes,
    required this.networkTxBytes,
    required this.uptimeMs,
  });

  /// Raw power-state string (`offline`/`starting`/`running`/`stopping`) —
  /// mapped to `ServerPowerState` in the repository, same convention as
  /// the WebSocket `status` event.
  final String currentState;

  final bool isSuspended;
  final double cpuAbsolutePercent;
  final int memoryBytes;
  final int diskBytes;
  final int networkRxBytes;
  final int networkTxBytes;
  final int uptimeMs;

  factory ServerResourceUsageDto.fromJson(Map<String, dynamic> json) {
    final resources = json['resources'];
    final resourcesMap = resources is Map<String, dynamic> ? resources : const <String, dynamic>{};

    return ServerResourceUsageDto(
      currentState: json['current_state'] as String? ?? 'offline',
      isSuspended: json['is_suspended'] as bool? ?? false,
      cpuAbsolutePercent: (resourcesMap['cpu_absolute'] as num?)?.toDouble() ?? 0,
      memoryBytes: (resourcesMap['memory_bytes'] as num?)?.toInt() ?? 0,
      diskBytes: (resourcesMap['disk_bytes'] as num?)?.toInt() ?? 0,
      networkRxBytes: (resourcesMap['network_rx_bytes'] as num?)?.toInt() ?? 0,
      networkTxBytes: (resourcesMap['network_tx_bytes'] as num?)?.toInt() ?? 0,
      uptimeMs: (resourcesMap['uptime'] as num?)?.toInt() ?? 0,
    );
  }
}
