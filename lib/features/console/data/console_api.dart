import '../../../core/error/result.dart';
import '../../../core/network/pterodactyl_api_client.dart';
import 'console_websocket_token_dto.dart';

/// Knows the one Pterodactyl Client API endpoint the console feature
/// needs. Built on a [PterodactylApiClient] that is already scoped to one
/// instance — same seam `ServersApi` uses, so this inherits the same
/// instance-isolation guarantees without adding any new ones.
class ConsoleApi {
  const ConsoleApi(this._client);

  final PterodactylApiClient _client;

  /// `GET /api/client/servers/{server}/websocket` — a one-time token
  /// (valid ~10 minutes) plus the exact `wss://` URL to connect to.
  ///
  /// Called again every time a connection or reconnection is needed —
  /// tokens are short-lived and never cached beyond a single connection
  /// attempt (see README, "Console — nie persystuj tokenów").
  Future<Result<ConsoleWebSocketTokenDto>> getWebsocketToken(String serverIdentifier) {
    return _client.get<ConsoleWebSocketTokenDto>(
      '/api/client/servers/$serverIdentifier/websocket',
      parser: (data) {
        if (data is! Map<String, dynamic> || data['data'] is! Map<String, dynamic>) {
          throw const FormatException(
            'Expected a {"data": {"token": ..., "socket": ...}} envelope from the websocket token endpoint.',
          );
        }
        return ConsoleWebSocketTokenDto.fromJson(data['data'] as Map<String, dynamic>);
      },
    );
  }
}
