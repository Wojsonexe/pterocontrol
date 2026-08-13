import '../../../core/error/result.dart';
import '../../../core/network/pterodactyl_api_client.dart';
import '../../../core/network/pterodactyl_envelope.dart';
import '../domain/server_power_action.dart';
import 'server_dto.dart';
import 'server_resource_usage_dto.dart';

/// One page of raw server data, as returned by [ServersApi.getServers].
typedef ServerPageDto = ({List<ServerDto> servers, PaginationMeta meta});

/// Knows the Pterodactyl Client API endpoints related to servers.
///
/// This is the seam the task description calls out explicitly: everything
/// below (`PterodactylApiClient`) is generic HTTP; everything here is
/// "what does the Pterodactyl API look like". Built on top of a
/// [PterodactylApiClient] that is already scoped to one instance — this
/// class has no knowledge of *which* instance it is talking to beyond that.
class ServersApi {
  const ServersApi(this._client);

  final PterodactylApiClient _client;

  /// `GET /api/client` — the authenticated user's server list, paginated.
  Future<Result<ServerPageDto>> getServers({int page = 1}) {
    return _client.get<ServerPageDto>(
      '/api/client',
      queryParameters: {'page': page},
      parser: (data) {
        final (items, meta) = PterodactylEnvelope.unwrapList(data);
        return (
          servers: items.map(ServerDto.fromJson).toList(growable: false),
          meta: meta ?? const PaginationMeta(currentPage: 1, totalPages: 1, total: 0, perPage: 0),
        );
      },
    );
  }

  /// `POST /api/client/servers/{server}/power` with body `{"signal": "..."}`.
  ///
  /// [serverIdentifier] is the short identifier from [ServerDto.identifier]
  /// (e.g. `d3aac109`), not the full UUID.
  Future<Result<void>> sendPowerAction(String serverIdentifier, ServerPowerAction action) {
    return _client.post<void>(
      '/api/client/servers/$serverIdentifier/power',
      data: {'signal': _signalFor(action)},
      parser: (_) {},
    );
  }

  /// `GET /api/client/servers/{server}` — a single server's current
  /// attributes. Same shape as one entry of [getServers], just scoped to
  /// one server — used for a *targeted* refresh (e.g. after Wings reports
  /// `install completed` over the console WebSocket) instead of re-fetching
  /// the whole list to learn one server's administrative status changed.
  Future<Result<ServerDto>> getServer(String serverIdentifier) {
    return _client.get<ServerDto>(
      '/api/client/servers/$serverIdentifier',
      parser: (data) => ServerDto.fromJson(PterodactylEnvelope.unwrapItem(data)),
    );
  }

  /// `GET /api/client/servers/{server}/resources` — live power state, CPU,
  /// memory, disk, network, uptime. Cached server-side for ~20s (see
  /// [ServerResourceUsageDto]'s doc comment) — callers should not poll
  /// faster than that.
  Future<Result<ServerResourceUsageDto>> getResourceUsage(String serverIdentifier) {
    return _client.get<ServerResourceUsageDto>(
      '/api/client/servers/$serverIdentifier/resources',
      parser: (data) => ServerResourceUsageDto.fromJson(PterodactylEnvelope.unwrapItem(data)),
    );
  }

  String _signalFor(ServerPowerAction action) => switch (action) {
        ServerPowerAction.start => 'start',
        ServerPowerAction.stop => 'stop',
        ServerPowerAction.restart => 'restart',
        ServerPowerAction.kill => 'kill',
      };
}
