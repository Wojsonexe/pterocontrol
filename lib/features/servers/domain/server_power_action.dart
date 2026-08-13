/// A power signal that can be sent to a server via the Pterodactyl Client
/// API's `POST /api/client/servers/{server}/power` endpoint.
///
/// This endpoint is fire-and-forget: a successful response means the
/// signal was accepted by Wings, not that the server has finished
/// transitioning to a new state. This app has no live power state yet
/// (no `.../resources` call, no WebSocket — see README) to observe that
/// transition, so callers should treat success as "command sent", not
/// "server is now running/stopped".
enum ServerPowerAction { start, stop, restart, kill }
