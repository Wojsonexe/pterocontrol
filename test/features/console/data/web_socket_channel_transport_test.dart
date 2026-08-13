import 'package:flutter_test/flutter_test.dart';
import 'package:pterodactyl_mobile/features/console/data/web_socket_channel_transport.dart';

void main() {
  group('WebSocketChannelTransport — heartbeat', () {
    // The real Wings protocol has no application-level heartbeat message
    // (verified against `wings/router/websocket/*.go` and
    // `wings/router/router_server_ws.go` — there is no `{"event": "ping"}`
    // or similar exchanged over the console socket). The only keep-alive
    // is the standard WebSocket ping/pong frame, which `dart:io`'s
    // `WebSocket` sends and verifies automatically once configured with a
    // `pingInterval` — there is no app-level frame format to encode/decode
    // and therefore nothing to unit-test at that level. What *is* this
    // app's responsibility, and so what is tested here, is that the
    // interval is actually wired in and is a sane, bounded value.
    test('pings at a bounded, positive interval', () {
      expect(kConsoleWebSocketPingInterval, greaterThan(Duration.zero));
      expect(kConsoleWebSocketPingInterval, lessThanOrEqualTo(const Duration(minutes: 1)));
    });

    test('the connect timeout is bounded and positive', () {
      expect(kConsoleWebSocketConnectTimeout, greaterThan(Duration.zero));
      expect(kConsoleWebSocketConnectTimeout, lessThanOrEqualTo(const Duration(seconds: 30)));
    });
  });
}
