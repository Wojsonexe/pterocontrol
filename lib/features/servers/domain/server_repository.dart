import 'server.dart';
import 'server_page.dart';
import 'server_power_action.dart';
import 'server_runtime_state.dart';

/// Fetches servers belonging to **one** Pterodactyl instance.
///
/// A [ServerRepository] is created already scoped to a specific instance
/// (see `features/instances/application/instance_api_client_provider.dart`
/// and `features/servers/application/servers_providers.dart`) — its
/// methods deliberately do not take an instance id, because "which
/// instance" is a construction-time fact, not a per-call parameter. This
/// makes it structurally impossible to accidentally query the wrong
/// instance's servers with the wrong instance's credentials; see README,
/// "Instance scoping".
///
/// Implementations translate any transport failure into an [AppException]
/// (thrown, not returned as a `Result`) — callers never see a `DioException`
/// or similar. This mirrors `InstanceRepository`'s convention.
abstract interface class ServerRepository {
  /// Fetches [page] (1-indexed) of this instance's servers.
  Future<ServerPage> getServers({int page = 1});

  /// Sends [action] to [serverIdentifier]. See [ServerPowerAction] for why
  /// success means "command accepted", not "server has changed state".
  Future<void> sendPowerAction(String serverIdentifier, ServerPowerAction action);

  /// Fetches [serverIdentifier]'s current attributes — a targeted,
  /// single-server counterpart to [getServers], used to refresh one
  /// already-known server without re-fetching the whole list. See
  /// `ServerListController.refreshOne`.
  Future<Server> getServer(String serverIdentifier);

  /// Fetches [serverIdentifier]'s live power state and resource usage
  /// (CPU/memory/disk/network/uptime) — see `ServerRuntimeState` and
  /// `ServerRuntimeSyncController`.
  Future<ServerRuntimeState> getResourceUsage(String serverIdentifier);
}
