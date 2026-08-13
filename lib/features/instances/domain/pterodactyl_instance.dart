import 'package:meta/meta.dart';

/// Result of the last reachability check performed for an instance.
///
/// This is runtime-only state — it reflects the last time the app checked,
/// not a persisted fact, and always starts at [unknown] after app restart.
enum InstanceConnectionStatus { unknown, checking, online, offline, error }

/// Whether the app currently holds credentials it believes are valid for
/// this instance.
///
/// [expired] is reserved for a future step where the app can tell a stored
/// credential apart from one the server has since rejected, without
/// deleting it outright.
enum InstanceAuthState { unauthenticated, authenticated, expired }

/// A single Pterodactyl Panel instance the user has added to the app.
///
/// This is a pure domain entity: it has no knowledge of HTTP, JSON, local
/// storage, or how it is persisted (see `data/instance_local_dto.dart` for
/// that). It also never carries credentials — those live in
/// `CredentialStorage`, keyed by [id].
@immutable
class PterodactylInstance {
  const PterodactylInstance({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.panelVersion,
    this.connectionStatus = InstanceConnectionStatus.unknown,
    this.authState = InstanceAuthState.unauthenticated,
  });

  /// Locally generated identifier, stable for the lifetime of the instance
  /// on this device. Not related to any identifier on the panel itself.
  final String id;

  final String name;

  /// Normalized (no trailing slash) base URL of the panel, e.g.
  /// `https://panel.example.com`.
  final String baseUrl;

  /// Panel version string, when known. Populated later by a capability/
  /// version-detection call — always `null` until that is implemented.
  final String? panelVersion;

  final InstanceConnectionStatus connectionStatus;

  final InstanceAuthState authState;

  PterodactylInstance copyWith({
    String? name,
    String? baseUrl,
    String? panelVersion,
    InstanceConnectionStatus? connectionStatus,
    InstanceAuthState? authState,
  }) {
    return PterodactylInstance(
      id: id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      panelVersion: panelVersion ?? this.panelVersion,
      connectionStatus: connectionStatus ?? this.connectionStatus,
      authState: authState ?? this.authState,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PterodactylInstance &&
        other.id == id &&
        other.name == name &&
        other.baseUrl == baseUrl &&
        other.panelVersion == panelVersion &&
        other.connectionStatus == connectionStatus &&
        other.authState == authState;
  }

  @override
  int get hashCode => Object.hash(
        id,
        name,
        baseUrl,
        panelVersion,
        connectionStatus,
        authState,
      );

  @override
  String toString() =>
      'PterodactylInstance(id: $id, name: $name, baseUrl: $baseUrl, '
      'connectionStatus: $connectionStatus, authState: $authState)';
}
