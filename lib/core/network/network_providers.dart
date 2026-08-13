import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client_factory.dart';

/// Shared [PterodactylApiClientFactory] used by every feature that needs to
/// talk to a Pterodactyl instance.
final apiClientFactoryProvider = Provider<PterodactylApiClientFactory>((ref) {
  return const PterodactylApiClientFactory();
});
