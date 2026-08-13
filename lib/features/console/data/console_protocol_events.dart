/// Wings WebSocket event name strings.
///
/// Verified against `wings/router/websocket/message.go` (the `Event`
/// constants) and `wings/server/events.go`. These are the wire protocol —
/// do not rename them to "look nicer"; they must match Wings exactly.
abstract final class ConsoleProtocolEvent {
  // Client -> Wings
  static const auth = 'auth';
  static const setState = 'set state';
  static const sendLogs = 'send logs';
  static const sendCommand = 'send command';
  static const sendStats = 'send stats';

  // Wings -> client
  static const authSuccess = 'auth success';
  static const tokenExpiring = 'token expiring';
  static const tokenExpired = 'token expired';
  static const jwtError = 'jwt error';
  static const daemonError = 'daemon error';
  static const throttled = 'throttled';
  static const consoleOutput = 'console output';
  static const installOutput = 'install output';
  static const installStarted = 'install started';
  static const installCompleted = 'install completed';
  static const daemonMessage = 'daemon message';
  static const status = 'status';
  static const stats = 'stats';

  /// Wings actually sends this as `"backup completed:<uuid>"` (event name
  /// plus a suffix) — see `wings/server/backup.go`. Matched with
  /// `startsWith` where needed, not equality.
  static const backupCompletedPrefix = 'backup completed';
  static const backupRestoreCompleted = 'backup restore completed';
  static const transferLogs = 'transfer logs';
  static const transferStatus = 'transfer status';
  static const deleted = 'deleted';
}
