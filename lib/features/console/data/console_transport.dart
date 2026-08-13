/// Abstraction over a single raw WebSocket connection.
///
/// `ConsoleWebSocketClient` (protocol codec) and `ConsoleRepositoryImpl`
/// (auth/reconnect orchestration) depend on this instead of any concrete
/// WebSocket library — mirroring how `core/network`'s
/// `FakeHttpClientAdapter` lets HTTP code be tested without a real
/// connection, this is the same idea applied to a streaming transport.
/// Tests inject a fake implementation; production uses
/// `WebSocketChannelTransport` (`package:web_socket_channel`).
abstract interface class ConsoleTransport {
  /// Incoming messages. Wings only ever sends text frames; anything else
  /// should be ignored by the caller rather than crash. The stream closes
  /// when the connection closes, for any reason (clean or not) — at that
  /// point [closeCode]/[closeReason] are populated.
  Stream<dynamic> get messages;

  /// Sends a text frame.
  Future<void> send(String data);

  /// Closes the connection. Safe to call more than once.
  Future<void> close([int? code, String? reason]);

  /// The WebSocket close code, once the connection has closed. `null`
  /// beforehand.
  int? get closeCode;

  /// The WebSocket close reason, once the connection has closed. `null`
  /// beforehand.
  String? get closeReason;
}

/// Opens a new [ConsoleTransport] connected to [url]. A plain typedef
/// (rather than a factory class) so tests can inject any function —
/// notably one that never touches a real socket.
typedef ConsoleTransportConnector = Future<ConsoleTransport> Function(Uri url);
