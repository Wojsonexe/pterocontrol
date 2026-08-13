import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pterodactyl_mobile/core/network/api_client_config.dart';
import 'package:pterodactyl_mobile/core/network/api_client_factory.dart';

void main() {
  test('the debug request logger never prints the Authorization header (token safety)', () async {
    final captured = StringBuffer();
    final originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) captured.writeln(message);
    };

    try {
      // Loopback + a port nothing listens on + a tight timeout: fails
      // almost instantly, with no dependency on real network/DNS. The
      // request-phase logging (what this test cares about) happens before
      // the connection attempt even completes, so the inevitable failure
      // is irrelevant here.
      const factory = PterodactylApiClientFactory(
        config: ApiClientConfig(connectTimeout: Duration(milliseconds: 300)),
      );
      final client = factory.createFor(
        baseUrl: 'http://127.0.0.1:1',
        authTokenProvider: () async => 'super-secret-token',
      );
      await client.get<void>('/api/client', parser: (_) {});
    } finally {
      debugPrint = originalDebugPrint;
    }

    final log = captured.toString();
    expect(log, isNot(contains('super-secret-token')));
    expect(log, isNot(contains('Authorization')));
  });
}
