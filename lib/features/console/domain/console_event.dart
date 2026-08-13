import 'package:meta/meta.dart';

/// The kind of a [ConsoleEvent].
///
/// Grounded in the real Wings WebSocket protocol
/// (`wings/router/websocket/message.go`, `wings/server/events.go`):
/// `console output` and `install output` both render as terminal-style
/// [output] (matching the reference Panel frontend, which feeds both into
/// the same terminal — `resources/scripts/components/server/console/Console.tsx`),
/// `daemon message`/`daemon error` are Wings' own informational/error
/// messages, kept distinct so the UI can style them differently.
enum ConsoleEventType {
  /// A line of console/game-server (or install script) output.
  output,

  /// An informational message from Wings itself (not the game process).
  daemonMessage,

  /// An error reported by Wings itself (not the game process).
  daemonError,

  /// A protocol event this app does not render as console text — e.g.
  /// `backup completed`, `transfer logs`, `install started`. Kept instead
  /// of silently dropping the frame, so nothing crashes and nothing
  /// vanishes without a trace; [ConsoleEvent.message] carries the raw
  /// event name for debugging.
  ///
  /// `status` and `stats` are *not* routed here even though they are also
  /// not console text: both update `ServerRuntimeState` instead (CPU/RAM/
  /// disk/network/uptime telemetry for `stats`, just the power state for
  /// `status`) — see that type and `ConsoleRepositoryImpl._handleStats`.
  unknown,
}

/// A single event on a server's live console stream.
///
/// Pure data — no WebSocket, no Dio, no Flutter. This is the type
/// `ConsoleRepository` parses incoming Wings frames into.
@immutable
class ConsoleEvent {
  const ConsoleEvent({required this.type, required this.message, required this.timestamp});

  final ConsoleEventType type;
  final String message;
  final DateTime timestamp;

  @override
  bool operator ==(Object other) {
    return other is ConsoleEvent &&
        other.type == type &&
        other.message == message &&
        other.timestamp == timestamp;
  }

  @override
  int get hashCode => Object.hash(type, message, timestamp);

  @override
  String toString() => 'ConsoleEvent(type: $type, message: $message, timestamp: $timestamp)';
}
