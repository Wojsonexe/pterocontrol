import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'console_transport.dart';

/// How often to send a WebSocket ping frame while connected.
///
/// This is the *only* keep-alive mechanism the real Wings protocol has —
/// verified against `wings/router/router_server_ws.go` and
/// `wings/router/websocket/*.go`: there is no application-level heartbeat
/// message (no `{"event": "ping"}` or similar). Wings relies entirely on
/// standard WebSocket ping/pong frames, which `dart:io`'s `WebSocket`
/// (via `IOWebSocketChannel`'s `pingInterval`) sends and verifies
/// automatically — if a pong isn't received within this interval, the
/// connection is closed by the transport itself, surfacing as a normal
/// disconnect that `ConsoleRepositoryImpl` reconnects from like any other.
const kConsoleWebSocketPingInterval = Duration(seconds: 20);

/// How long to wait for the WebSocket handshake to complete before giving
/// up and surfacing an error.
const kConsoleWebSocketConnectTimeout = Duration(seconds: 10);

/// [ConsoleTransport] backed by a real `dart:io` WebSocket
/// (`package:web_socket_channel`).
class WebSocketChannelTransport implements ConsoleTransport {
  WebSocketChannelTransport._(this._channel);

  final WebSocketChannel _channel;

  /// Connects to [url].
  ///
  /// [origin] is sent as the `Origin` header on the handshake. Wings
  /// rejects the upgrade unless the `Origin` header matches the Panel's
  /// own configured location (or an entry in Wings' `allowed_origins`) —
  /// see `wings/router/websocket/websocket.go`'s `CheckOrigin`. A native
  /// mobile client has no natural browser-style origin, so this app sends
  /// the instance's own Panel URL, which is what a typical Wings
  /// configuration already allows (it is, after all, the Panel it talks
  /// to for everything else).
  static Future<ConsoleTransport> connect(Uri url, {required String origin}) async {
    final channel = IOWebSocketChannel.connect(
      url,
      headers: {'Origin': origin},
      pingInterval: kConsoleWebSocketPingInterval,
      connectTimeout: kConsoleWebSocketConnectTimeout,
    );
    await channel.ready;
    return WebSocketChannelTransport._(channel);
  }

  @override
  Stream<dynamic> get messages => _channel.stream;

  @override
  Future<void> send(String data) async => _channel.sink.add(data);

  @override
  Future<void> close([int? code, String? reason]) => _channel.sink.close(code, reason);

  @override
  int? get closeCode => _channel.closeCode;

  @override
  String? get closeReason => _channel.closeReason;
}
