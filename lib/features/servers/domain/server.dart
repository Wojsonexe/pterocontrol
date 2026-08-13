import 'package:meta/meta.dart';

/// Administrative state of a server, as reported by the Pterodactyl Client
/// API's `status` field.
///
/// This is **not** the live power state (running / starting / stopping /
/// offline) — that comes from a per-server resource-usage call or the
/// WebSocket connection, neither of which this milestone implements (see
/// README). `GET /api/client` only ever tells us whether the server is in
/// one of these administrative states, or [active] (the API returns `null`
/// when none of them apply).
enum ServerAdministrativeStatus {
  active,
  installing,
  installFailed,
  reinstallFailed,
  suspended,
  restoringBackup,

  /// Any status string the API returns that this app does not recognize
  /// yet. Keeps the app forward-compatible with new Pterodactyl states
  /// instead of crashing on them.
  unknown,
}

/// Resource limits configured for a server, as needed to give the user a
/// basic sense of its size on the list/detail screens.
@immutable
class ServerLimits {
  const ServerLimits({
    required this.memoryMb,
    required this.diskMb,
    required this.cpuPercent,
  });

  final int memoryMb;
  final int diskMb;

  /// CPU limit as a percentage of one core (100 = one full core), matching
  /// how Pterodactyl itself expresses it. `0` means unlimited.
  final int cpuPercent;

  @override
  bool operator ==(Object other) {
    return other is ServerLimits &&
        other.memoryMb == memoryMb &&
        other.diskMb == diskMb &&
        other.cpuPercent == cpuPercent;
  }

  @override
  int get hashCode => Object.hash(memoryMb, diskMb, cpuPercent);
}

/// A single server belonging to some Pterodactyl instance.
///
/// Deliberately minimal: only what the server list, the detail screen, and
/// future power actions (start/stop/restart, keyed by [identifier]) need.
/// Pterodactyl's `GET /api/client` response carries more fields (SFTP
/// details, egg/docker image info, feature limits, relationships, ...) —
/// none of that is copied here until a concrete feature needs it; see
/// `ServerDto` for the raw shape and README for how to extend this.
@immutable
class Server {
  const Server({
    required this.identifier,
    required this.uuid,
    required this.name,
    required this.node,
    required this.status,
    required this.isTransferring,
    required this.limits,
    this.description,
  });

  /// Short identifier used in Client API URLs (e.g. `d3aac109`).
  final String identifier;

  /// Full UUID — not used for REST calls, but needed later for the
  /// WebSocket protocol.
  final String uuid;

  final String name;

  /// `null` when the panel returned an empty description — there is no
  /// meaningful difference between "no description" and "" for this app.
  final String? description;

  /// Name of the Wings node hosting this server.
  final String node;

  final ServerAdministrativeStatus status;

  /// Whether the server is currently being transferred to another node.
  final bool isTransferring;

  final ServerLimits limits;

  @override
  bool operator ==(Object other) {
    return other is Server &&
        other.identifier == identifier &&
        other.uuid == uuid &&
        other.name == name &&
        other.description == description &&
        other.node == node &&
        other.status == status &&
        other.isTransferring == isTransferring &&
        other.limits == limits;
  }

  @override
  int get hashCode => Object.hash(
        identifier,
        uuid,
        name,
        description,
        node,
        status,
        isTransferring,
        limits,
      );

  @override
  String toString() => 'Server(identifier: $identifier, name: $name, status: $status)';
}
