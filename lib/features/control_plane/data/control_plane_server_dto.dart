import '../domain/control_plane_resource_usage.dart';
import '../domain/control_plane_server.dart';

/// Raw shape of one row from `GET /servers` on `services/control-plane-api`
/// — the Prisma `Server` model, returned as-is by `ServersController`
/// (`src/servers/servers.controller.ts`), not wrapped in any envelope.
/// Only the fields this app's MVP slice actually uses are parsed; the rest
/// of the row (`tenantId`, `pterodactylId`, `pterodactylUuid`, `createdAt`)
/// is redundant here (tenant is implicit to the logged-in session) or
/// unused by any screen yet.
ControlPlaneServer controlPlaneServerFromJson(Map<String, dynamic> json) {
  return ControlPlaneServer(
    id: json['id'] as String,
    instanceId: json['instanceId'] as String,
    identifier: json['identifier'] as String,
    name: json['name'] as String,
    nodeId: json['nodeId'] as int,
    lastSyncedAt: DateTime.parse(json['lastSyncedAt'] as String),
  );
}

/// Raw shape of `GET /servers/:id/resources` — direct pass-through of
/// `PterodactylResourceUsageDto` from `@pterocontrol/pterodactyl-sdk`.
ControlPlaneResourceUsage controlPlaneResourceUsageFromJson(Map<String, dynamic> json) {
  return ControlPlaneResourceUsage(
    currentState: json['currentState'] as String,
    isSuspended: json['isSuspended'] as bool,
    cpuAbsolutePercent: (json['cpuAbsolutePercent'] as num).toDouble(),
    memoryBytes: (json['memoryBytes'] as num).toInt(),
    diskBytes: (json['diskBytes'] as num).toInt(),
    networkRxBytes: (json['networkRxBytes'] as num).toInt(),
    networkTxBytes: (json['networkTxBytes'] as num).toInt(),
    uptimeMs: (json['uptimeMs'] as num).toInt(),
  );
}
