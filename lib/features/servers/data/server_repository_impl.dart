import '../domain/server.dart';
import '../domain/server_page.dart';
import '../domain/server_power_action.dart';
import '../domain/server_power_state.dart';
import '../domain/server_repository.dart';
import '../domain/server_runtime_state.dart';
import 'server_dto.dart';
import 'servers_api.dart';

/// [ServerRepository] backed by [ServersApi].
///
/// This is the boundary where the `Result<T>` returned by
/// `PterodactylApiClient`/[ServersApi] gets translated into the
/// throw-based error convention the rest of the app's repositories use
/// (see `InstanceRepository`) — callers of [getServers] never see a
/// `Result`, only a value or a thrown `AppException`.
class ServerRepositoryImpl implements ServerRepository {
  const ServerRepositoryImpl(this._api);

  final ServersApi _api;

  @override
  Future<ServerPage> getServers({int page = 1}) async {
    final result = await _api.getServers(page: page);
    return result.fold(
      onSuccess: (data) => ServerPage(
        servers: data.servers.map(_toDomain).toList(growable: false),
        page: data.meta.currentPage,
        totalPages: data.meta.totalPages,
      ),
      onFailure: (error) => throw error,
    );
  }

  Server _toDomain(ServerDto dto) {
    return Server(
      identifier: dto.identifier,
      uuid: dto.uuid,
      name: dto.name,
      description: (dto.description == null || dto.description!.isEmpty) ? null : dto.description,
      node: dto.node,
      status: _statusFromRaw(dto.status),
      isTransferring: dto.isTransferring,
      limits: ServerLimits(
        memoryMb: dto.memoryMb,
        diskMb: dto.diskMb,
        cpuPercent: dto.cpuPercent,
      ),
    );
  }

  @override
  Future<void> sendPowerAction(String serverIdentifier, ServerPowerAction action) async {
    final result = await _api.sendPowerAction(serverIdentifier, action);
    return result.fold(onSuccess: (_) {}, onFailure: (error) => throw error);
  }

  @override
  Future<Server> getServer(String serverIdentifier) async {
    final result = await _api.getServer(serverIdentifier);
    return result.fold(onSuccess: _toDomain, onFailure: (error) => throw error);
  }

  @override
  Future<ServerRuntimeState> getResourceUsage(String serverIdentifier) async {
    final result = await _api.getResourceUsage(serverIdentifier);
    return result.fold(
      onSuccess: (dto) => ServerRuntimeState(
        powerState: _powerStateFromRaw(dto.currentState),
        observedAt: DateTime.now(),
        cpuAbsolutePercent: dto.cpuAbsolutePercent,
        memoryBytes: dto.memoryBytes,
        diskBytes: dto.diskBytes,
        networkRxBytes: dto.networkRxBytes,
        networkTxBytes: dto.networkTxBytes,
        uptimeMs: dto.uptimeMs,
      ),
      onFailure: (error) => throw error,
    );
  }

  /// Same mapping `ConsoleRepositoryImpl` applies to the WebSocket `status`
  /// event — both read the exact same set of strings Wings emits
  /// (`offline`/`starting`/`running`/`stopping`), just over different
  /// transports for the same underlying `environment.Stats`/`ResourceUsage`
  /// state.
  ServerPowerState _powerStateFromRaw(String raw) {
    return switch (raw) {
      'offline' => ServerPowerState.offline,
      'starting' => ServerPowerState.starting,
      'running' => ServerPowerState.running,
      'stopping' => ServerPowerState.stopping,
      _ => ServerPowerState.unknown,
    };
  }

  ServerAdministrativeStatus _statusFromRaw(String? raw) {
    return switch (raw) {
      null => ServerAdministrativeStatus.active,
      'installing' => ServerAdministrativeStatus.installing,
      'install_failed' => ServerAdministrativeStatus.installFailed,
      'reinstall_failed' => ServerAdministrativeStatus.reinstallFailed,
      'suspended' => ServerAdministrativeStatus.suspended,
      'restoring_backup' => ServerAdministrativeStatus.restoringBackup,
      _ => ServerAdministrativeStatus.unknown,
    };
  }
}
