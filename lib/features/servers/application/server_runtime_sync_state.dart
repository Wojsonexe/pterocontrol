import 'package:meta/meta.dart';

import '../domain/server_metrics_history.dart';
import '../domain/server_runtime_state.dart';

/// How `ServerRuntimeSyncController` is currently doing, for the small
/// "Live / Reconnecting / Offline" indicator — see
/// `sync_status_indicator.dart`. Deliberately just three states: this is
/// polling, not a connection with its own lifecycle, so there is no
/// separate "connecting" state distinct from the initial `syncing`.
enum ServerSyncStatus {
  /// No poll has completed yet since this controller was created.
  syncing,

  /// The most recent poll succeeded for at least one server.
  live,

  /// The most recent poll failed for every server (e.g. no network).
  /// [ServerRuntimeSyncState.runtimeByServer] keeps whatever was last
  /// known — never cleared on a failed poll.
  offline,
}

/// State exposed by `ServerRuntimeSyncController`: the live runtime
/// reading last seen for each server (keyed by [ServerDto.identifier]/
/// `Server.identifier`), plus the overall sync status.
@immutable
class ServerRuntimeSyncState {
  const ServerRuntimeSyncState({
    this.runtimeByServer = const {},
    this.historyByServer = const {},
    this.refreshingIdentifiers = const {},
    this.failedIdentifiers = const {},
    this.status = ServerSyncStatus.syncing,
  });

  final Map<String, ServerRuntimeState> runtimeByServer;

  /// A short rolling window of real samples per server, for sparklines —
  /// see `ServerMetricsHistory`. Keyed the same as [runtimeByServer]; a
  /// server missing here simply has no history widget to show yet (its
  /// first poll hasn't landed), never a placeholder/synthesized one.
  final Map<String, ServerMetricsHistory> historyByServer;

  /// Servers whose `.../resources` fetch is *currently in flight* — a
  /// server can be in here while [runtimeByServer] still holds an older
  /// reading for it (a refresh in progress must never blank out what's
  /// already known). Drives the small "still updating" indicator on an
  /// already-populated card, and — combined with an *absent*
  /// [runtimeByServer] entry — the "first load" skeleton state.
  final Set<String> refreshingIdentifiers;

  /// Servers whose most recent fetch attempt failed — cleared the moment
  /// that server's next attempt succeeds. Never implies "no data": a
  /// server can be in here while [runtimeByServer] still holds its last
  /// good reading, which the UI keeps showing (with a small "nie udało
  /// się odświeżyć" caption) rather than blanking out.
  final Set<String> failedIdentifiers;

  final ServerSyncStatus status;

  ServerRuntimeState? runtimeFor(String serverIdentifier) => runtimeByServer[serverIdentifier];

  ServerMetricsHistory historyFor(String serverIdentifier) =>
      historyByServer[serverIdentifier] ?? ServerMetricsHistory.empty;

  bool isRefreshing(String serverIdentifier) => refreshingIdentifiers.contains(serverIdentifier);

  bool hasRecentFailure(String serverIdentifier) => failedIdentifiers.contains(serverIdentifier);

  ServerRuntimeSyncState copyWith({
    Map<String, ServerRuntimeState>? runtimeByServer,
    Map<String, ServerMetricsHistory>? historyByServer,
    Set<String>? refreshingIdentifiers,
    Set<String>? failedIdentifiers,
    ServerSyncStatus? status,
  }) {
    return ServerRuntimeSyncState(
      runtimeByServer: runtimeByServer ?? this.runtimeByServer,
      historyByServer: historyByServer ?? this.historyByServer,
      refreshingIdentifiers: refreshingIdentifiers ?? this.refreshingIdentifiers,
      failedIdentifiers: failedIdentifiers ?? this.failedIdentifiers,
      status: status ?? this.status,
    );
  }
}
