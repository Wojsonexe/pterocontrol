import 'package:meta/meta.dart';

import 'server_power_state.dart';

/// Everything the app currently believes about one server's *live* runtime
/// state, and how fresh that belief is — not just the raw
/// [ServerPowerState] value.
///
/// Has two producers, both feeding the same shape (deliberately — see
/// README, "Synchronizacja stanu serwerów"):
/// - `ConsoleRepositoryImpl`, from the WebSocket `status`/`stats` events,
///   while a server's console is connected (richer/more current; resource
///   fields come from `stats`, matching Wings' `environment.Stats`
///   exactly — see `server_resource_usage_dto.dart`'s doc comment for the
///   verified field mapping).
/// - `ServerRuntimeSyncController`, from polling
///   `GET /api/client/servers/{server}/resources` for whichever servers
///   are currently loaded in a list/dashboard — the same endpoint, and the
///   same 30s interval, the reference Panel dashboard itself polls at for
///   exactly this purpose (tuned just above that endpoint's own 20s
///   server-side cache — see `server_resource_usage_dto.dart`).
@immutable
class ServerRuntimeState {
  const ServerRuntimeState({
    required this.powerState,
    this.observedAt,
    this.cpuAbsolutePercent,
    this.memoryBytes,
    this.diskBytes,
    this.networkRxBytes,
    this.networkTxBytes,
    this.uptimeMs,
  });

  /// The state before any live reading has ever arrived for a server this
  /// session — the correct initial value for a future controller's `build`.
  static const ServerRuntimeState unknown = ServerRuntimeState(powerState: ServerPowerState.unknown);

  final ServerPowerState powerState;

  /// When this reading was received. `null` iff [powerState] is
  /// [ServerPowerState.unknown] — there is nothing to timestamp yet.
  final DateTime? observedAt;

  /// CPU usage relative to the whole system (not the server's own limit —
  /// matches Wings' `cpu_absolute`), `null` until a reading arrives.
  final double? cpuAbsolutePercent;

  final int? memoryBytes;
  final int? diskBytes;
  final int? networkRxBytes;
  final int? networkTxBytes;

  /// Container uptime, in milliseconds (matches Wings' `uptime`).
  final int? uptimeMs;

  /// Whether any resource reading (not just a power-state reading) has
  /// ever arrived — controls whether the UI shows live metrics or falls
  /// back to the server's configured limits.
  bool get hasResourceReading => cpuAbsolutePercent != null;

  ServerRuntimeState copyWith({
    ServerPowerState? powerState,
    DateTime? observedAt,
    double? cpuAbsolutePercent,
    int? memoryBytes,
    int? diskBytes,
    int? networkRxBytes,
    int? networkTxBytes,
    int? uptimeMs,
  }) {
    return ServerRuntimeState(
      powerState: powerState ?? this.powerState,
      observedAt: observedAt ?? this.observedAt,
      cpuAbsolutePercent: cpuAbsolutePercent ?? this.cpuAbsolutePercent,
      memoryBytes: memoryBytes ?? this.memoryBytes,
      diskBytes: diskBytes ?? this.diskBytes,
      networkRxBytes: networkRxBytes ?? this.networkRxBytes,
      networkTxBytes: networkTxBytes ?? this.networkTxBytes,
      uptimeMs: uptimeMs ?? this.uptimeMs,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ServerRuntimeState &&
        other.powerState == powerState &&
        other.observedAt == observedAt &&
        other.cpuAbsolutePercent == cpuAbsolutePercent &&
        other.memoryBytes == memoryBytes &&
        other.diskBytes == diskBytes &&
        other.networkRxBytes == networkRxBytes &&
        other.networkTxBytes == networkTxBytes &&
        other.uptimeMs == uptimeMs;
  }

  @override
  int get hashCode => Object.hash(
        powerState,
        observedAt,
        cpuAbsolutePercent,
        memoryBytes,
        diskBytes,
        networkRxBytes,
        networkTxBytes,
        uptimeMs,
      );

  @override
  String toString() =>
      'ServerRuntimeState(powerState: $powerState, observedAt: $observedAt, '
      'cpu: $cpuAbsolutePercent%, memory: $memoryBytes B, uptime: $uptimeMs ms)';
}
