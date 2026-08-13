import '../../servers/domain/server_runtime_state.dart';
import 'console_connection_state.dart';
import 'console_event.dart';

/// Owns one server's live console connection: authentication, the
/// WebSocket itself, reconnects, and mapping raw Wings frames into this
/// app's domain types.
///
/// A [ConsoleRepository] is scoped to exactly one `ConsoleTarget`
/// (one server on one instance) at construction time — like
/// `ServerRepository`, it has no method that takes an instance/server id,
/// because "which server" is a construction-time fact, not a per-call
/// parameter. See README, "Instance scoping".
///
/// All three streams are broadcast streams that only emit *changes* going
/// forward — callers must subscribe before calling [connect] to avoid
/// missing the first transition (the `ConsoleController` does this).
abstract interface class ConsoleRepository {
  /// Lifecycle of the underlying WebSocket connection.
  Stream<ConsoleConnectionState> get connectionState;

  /// The server's live runtime/power state as reported by Wings over this
  /// connection — independent of [connectionState] (e.g. still
  /// [ServerPowerState.unknown] immediately after connecting, until the
  /// first `status` event arrives).
  Stream<ServerRuntimeState> get runtimeState;

  /// The current console buffer, emitted in full on every change (bounded
  /// — see the implementation for the exact limit and rationale). The UI
  /// only ever needs "whatever the latest value is", never an incremental
  /// delta.
  Stream<List<ConsoleEvent>> get events;

  /// Opens the connection: fetches a websocket token via the Client API,
  /// connects, and authenticates. No-op if already connected or
  /// connecting. Failures are reported through [connectionState]
  /// (`ConsoleConnectionState.error`), not thrown.
  Future<void> connect();

  /// Closes the connection intentionally. No reconnect is attempted
  /// afterward unless [connect] is called again.
  Future<void> disconnect();

  /// Sends a command to the server's console. A no-op if not currently
  /// connected — never throws, matching the fire-and-forget nature of the
  /// rest of the console protocol.
  void sendCommand(String command);

  /// Releases all resources: closes the connection, cancels any pending
  /// reconnect timer, and closes the streams above. Safe to call even if
  /// [connect] was never called.
  Future<void> dispose();
}
