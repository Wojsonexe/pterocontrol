/// The server's **actual** runtime power state, as reported live by Wings —
/// via `GET /api/client/servers/{server}/resources`
/// (`ServerRuntimeSyncController`) or the WebSocket `status`/`stats` events
/// (`ConsoleRepositoryImpl`, while a server's console is connected).
///
/// Deliberately a separate type from `ServerAdministrativeStatus`
/// (`server.dart`): that one comes from the Panel's `GET /api/client` list
/// response and reflects administrative state (installing, suspended, ...);
/// this one reflects whether the game server process itself is up. A
/// server can be [ServerAdministrativeStatus.active] and
/// [ServerPowerState.offline] at the same time — "allowed to run" and
/// "currently running" are independent facts.
enum ServerPowerState {
  /// No live reading has been received (nothing is connected/watching yet).
  unknown,
  offline,
  starting,
  running,
  stopping,
}
