import '../../../core/error/result.dart';
import '../domain/control_plane_power_action.dart';
import '../domain/control_plane_resource_usage.dart';
import '../domain/control_plane_server.dart';
import 'control_plane_api_client.dart';
import 'control_plane_server_dto.dart';

/// Wraps the server endpoints of `services/control-plane-api`
/// (`src/servers/servers.controller.ts`) this MVP slice needs: list,
/// live resource usage, and power control. Deliberately does not cover
/// every module built on that backend this session (alerts, notifications,
/// backups, schedules, ...) — see IMPLEMENTATION_STATUS.md, "Zakres
/// pierwszego, wąskiego MVP-slice'a".
class ControlPlaneServersApi {
  const ControlPlaneServersApi(this._client);

  final ControlPlaneApiClient _client;

  Future<Result<List<ControlPlaneServer>>> list() {
    return _client.get<List<ControlPlaneServer>>(
      '/servers',
      parser: (data) => (data as List<dynamic>)
          .map((row) => controlPlaneServerFromJson(row as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<Result<ControlPlaneResourceUsage>> getResources(String serverId) {
    return _client.get<ControlPlaneResourceUsage>(
      '/servers/$serverId/resources',
      parser: (data) => controlPlaneResourceUsageFromJson(data as Map<String, dynamic>),
    );
  }

  /// Fire-and-forget, same semantics as the Pterodactyl-direct
  /// equivalent (`ServerPowerAction`'s own doc comment) — a `202` response
  /// means the Control Plane backend queued the signal, not that the
  /// server finished transitioning. RBAC-gated server-side to
  /// `owner`/`admin`; a `viewer`-role user gets a real `403` ->
  /// `ForbiddenException`, not a client-side guess about their role.
  Future<Result<void>> sendPowerAction(String serverId, ControlPlanePowerAction action) {
    return _client.post<void>(
      '/servers/$serverId/power',
      data: {'action': action.name},
      parser: (_) {},
    );
  }
}
