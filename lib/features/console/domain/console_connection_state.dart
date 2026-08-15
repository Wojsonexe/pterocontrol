/// Lifecycle of the app's live connection to one server's console —
/// the transport's own state, independent of what it is carrying.
///
/// Deliberately **not** the same type as `InstanceConnectionStatus`
/// (`features/instances/domain/pterodactyl_instance.dart`): that one
/// reflects whether the Panel's REST API is reachable for a whole
/// instance (checked by `InstanceListController.checkConnection`); this
/// one reflects one server's own WebSocket session. Conflating them
/// would mean the instances feature's domain leaking into a concern
/// (live per-server sessions) it has no business knowing about.
///
/// [connecting] and [authenticating] are deliberately distinct: opening
/// the transport (a TCP/TLS handshake, wholly outside this app's
/// control) and the `auth`/`auth success` round trip Wings itself
/// requires (see `ConsoleRepositoryImpl._attemptConnect`) are two
/// different things that can each stall for different reasons — a slow
/// network vs. a Wings node that accepted the socket but is not
/// responding to auth. See [ConsoleRepositoryImpl] for the sole producer.
enum ConsoleConnectionState { disconnected, connecting, authenticating, connected, reconnecting, error }
