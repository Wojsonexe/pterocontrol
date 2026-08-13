/// Raw shape of a Wings WebSocket frame: `{"event": "...", "args": [...]}`.
///
/// Verified against `wings/router/websocket/message.go`'s `Message` struct
/// — every frame in both directions uses exactly this shape. Kept separate
/// from the domain `ConsoleEvent` the same way `ServerDto` is kept
/// separate from `Server`: this is the wire format, not what the rest of
/// the app should reason about.
class ConsoleProtocolMessage {
  const ConsoleProtocolMessage({required this.event, this.args = const []});

  final String event;
  final List<String> args;

  /// The `args` array joined back together — this is how Wings itself
  /// reconstitutes a single value split across the array (see
  /// `strings.Join(m.Args, "")` in `websocket.go`'s inbound handler for
  /// the `auth` event; the same convention applies to single-value
  /// outbound args like `console output`/`daemon message`/`status`).
  String get joinedArgs => args.join();

  factory ConsoleProtocolMessage.fromJson(Map<String, dynamic> json) {
    final event = json['event'];
    if (event is! String) {
      throw const FormatException('Expected a Wings websocket frame with a string "event" field.');
    }
    final rawArgs = json['args'];
    final args = rawArgs is List ? rawArgs.map((e) => e.toString()).toList(growable: false) : const <String>[];
    return ConsoleProtocolMessage(event: event, args: args);
  }

  Map<String, dynamic> toJson() {
    return {'event': event, if (args.isNotEmpty) 'args': args};
  }
}
