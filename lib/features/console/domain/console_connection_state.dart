/// Lifecycle of the app's live connection to one server's console —
/// the transport's own state, independent of what it is carrying.
///
/// Deliberately **not** the same type as `InstanceConnectionStatus`
/// (`features/instances/domain/pterodactyl_instance.dart`): that one
/// reflects whether the Panel's REST API is reachable for a whole
/// instance (checked by `InstanceListController.checkConnection`); this
/// one will reflect one server's own WebSocket session. Conflating them
/// would mean the instances feature's domain leaking into a concern
/// (live per-server sessions) it has no business knowing about.
///
/// No producer of this state exists yet — see README, "Console (fundament
/// pod WebSocket)".
enum ConsoleConnectionState { disconnected, connecting, connected, reconnecting, error }
