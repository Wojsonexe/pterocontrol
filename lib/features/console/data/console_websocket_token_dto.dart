/// Raw response of `GET /api/client/servers/{server}/websocket`.
///
/// Mirrors the Panel's actual response shape exactly — verified against
/// `panel/app/Http/Controllers/Api/Client/Servers/WebsocketController.php`:
/// `{"data": {"token": "...", "socket": "wss://..."}}`. **Not** the usual
/// Fractal `{"object": ..., "attributes": {...}}` envelope every other
/// Client API response uses — this endpoint is a deliberate exception on
/// the Panel side, so `PterodactylEnvelope` does not apply here.
class ConsoleWebSocketTokenDto {
  const ConsoleWebSocketTokenDto({required this.token, required this.socketUrl});

  /// Short-lived (10 minute) JWT sent as the WebSocket `auth` message.
  final String token;

  /// Full `wss://`/`ws://` URL to connect to, already resolved to the
  /// correct node (including mid-transfer redirection to the target node,
  /// handled Panel-side).
  final String socketUrl;

  factory ConsoleWebSocketTokenDto.fromJson(Map<String, dynamic> json) {
    return ConsoleWebSocketTokenDto(
      token: json['token'] as String,
      socketUrl: json['socket'] as String,
    );
  }
}
