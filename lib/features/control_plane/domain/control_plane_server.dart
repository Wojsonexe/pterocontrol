import 'package:meta/meta.dart';

/// A server as reported by the Control Plane's global server model
/// (`GET /servers` on `services/control-plane-api`) — mirrors the real
/// Prisma `Server` row returned by that endpoint, not a Pterodactyl Client
/// API server object (see `features/servers/domain/server.dart` for that,
/// a different type entirely).
@immutable
class ControlPlaneServer {
  const ControlPlaneServer({
    required this.id,
    required this.instanceId,
    required this.identifier,
    required this.name,
    required this.nodeId,
    required this.lastSyncedAt,
  });

  /// Control Plane's own global id, not the Pterodactyl-side numeric id.
  final String id;

  /// The `PterodactylInstance` (panel) this server was synced from, on the
  /// Control Plane backend side — distinct from anything in this app's own
  /// `features/instances`.
  final String instanceId;

  final String identifier;
  final String name;
  final int nodeId;
  final DateTime lastSyncedAt;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ControlPlaneServer &&
        other.id == id &&
        other.instanceId == instanceId &&
        other.identifier == identifier &&
        other.name == name &&
        other.nodeId == nodeId &&
        other.lastSyncedAt == lastSyncedAt;
  }

  @override
  int get hashCode => Object.hash(id, instanceId, identifier, name, nodeId, lastSyncedAt);
}
