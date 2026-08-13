import 'package:meta/meta.dart';

import '../../servers/domain/server_runtime_state.dart';
import '../domain/console_connection_state.dart';
import '../domain/console_event.dart';

/// Everything `ConsoleController` exposes to the UI for one server's
/// console: connection lifecycle, live power state, and the buffered
/// output — bundled together because the console screen always needs all
/// three at once (e.g. to show a status indicator *and* the output *and*
/// know when to show an empty state).
@immutable
class ConsoleState {
  const ConsoleState({required this.connectionState, required this.runtimeState, required this.events});

  /// The state before any stream has emitted yet — the correct initial
  /// value for `ConsoleController.build`.
  static const initial = ConsoleState(
    connectionState: ConsoleConnectionState.disconnected,
    runtimeState: ServerRuntimeState.unknown,
    events: [],
  );

  final ConsoleConnectionState connectionState;
  final ServerRuntimeState runtimeState;
  final List<ConsoleEvent> events;

  ConsoleState copyWith({
    ConsoleConnectionState? connectionState,
    ServerRuntimeState? runtimeState,
    List<ConsoleEvent>? events,
  }) {
    return ConsoleState(
      connectionState: connectionState ?? this.connectionState,
      runtimeState: runtimeState ?? this.runtimeState,
      events: events ?? this.events,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ConsoleState &&
        other.connectionState == connectionState &&
        other.runtimeState == runtimeState &&
        _listEquals(other.events, events);
  }

  @override
  int get hashCode => Object.hash(connectionState, runtimeState, Object.hashAll(events));

  @override
  String toString() {
    return 'ConsoleState(connectionState: $connectionState, runtimeState: $runtimeState, '
        'events: ${events.length} line(s))';
  }
}

bool _listEquals(List<ConsoleEvent> a, List<ConsoleEvent> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
