import 'dart:async';
import 'dart:convert';

import 'console_protocol_message.dart';
import 'console_transport.dart';

/// Thin protocol codec over a [ConsoleTransport]: encodes/decodes the
/// `{"event": ..., "args": [...]}` frames Wings speaks. Knows nothing
/// about authentication, reconnects, or what any particular event *means*
/// — that is `ConsoleRepositoryImpl`'s job. This mirrors
/// `PterodactylApiClient`'s role for REST: a generic transport wrapper,
/// not endpoint/protocol-semantics-aware.
///
/// Scoped to a single connection attempt — create a new
/// [ConsoleWebSocketClient] for every (re)connect, the same way a new
/// [ConsoleTransport] is opened for every attempt.
class ConsoleWebSocketClient {
  ConsoleWebSocketClient(this._transport) {
    _subscription = _transport.messages.listen(
      _handleRawMessage,
      onDone: () => _doneCompleter.complete(),
      onError: (Object error, StackTrace stackTrace) => _doneCompleter.complete(),
      cancelOnError: true,
    );
  }

  final ConsoleTransport _transport;
  final _messages = StreamController<ConsoleProtocolMessage>.broadcast();
  final _doneCompleter = Completer<void>();
  StreamSubscription<dynamic>? _subscription;

  /// Successfully decoded frames. Malformed frames (not JSON, not an
  /// object, missing/non-string `event`) are dropped rather than
  /// forwarded — matching Wings' own behavior for frames *it* receives
  /// (`router_server_ws.go`: `if err := json.Unmarshal(p, &j); err != nil
  /// { continue }`), and consistent with "never crash the console over a
  /// single bad frame".
  Stream<ConsoleProtocolMessage> get messages => _messages.stream;

  /// Completes once the underlying transport closes, for any reason.
  Future<void> get done => _doneCompleter.future;

  int? get closeCode => _transport.closeCode;
  String? get closeReason => _transport.closeReason;

  void _handleRawMessage(dynamic raw) {
    if (raw is! String) return;
    final dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return;
    }
    if (decoded is! Map<String, dynamic>) return;
    try {
      _messages.add(ConsoleProtocolMessage.fromJson(decoded));
    } on FormatException {
      return;
    }
  }

  /// Sends `{"event": event, "args": [...args]}`. [args] defaults to an
  /// empty list — most inbound events (`send logs`, `send stats`) take
  /// none.
  Future<void> send(String event, [List<String> args = const []]) {
    return _transport.send(jsonEncode(ConsoleProtocolMessage(event: event, args: args).toJson()));
  }

  Future<void> close([int code = 1000, String? reason]) async {
    await _transport.close(code, reason);
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _messages.close();
  }
}
