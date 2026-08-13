import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/network_providers.dart';
import '../../../core/network/pterodactyl_api_client.dart';
import '../../authentication/application/credential_storage_provider.dart';
import '../domain/pterodactyl_instance.dart';
import 'instance_list_controller.dart';

/// Resolves the [PterodactylInstance] registered under [instanceId],
/// throwing if none exists.
///
/// Extracted out of [instanceApiClientProvider] so this lookup has exactly
/// one implementation: today it is only needed to build a REST client
/// (below), but a future WebSocket connection is *also* scoped to
/// `(instanceId, serverIdentifier)` and will need the same instance (e.g.
/// to turn its `baseUrl` into a `wss://` URL) — without this seam, that
/// feature would have to duplicate the lookup-or-throw logic instead of
/// depending on it.
///
/// `autoDispose`: no reason to keep a resolved instance around once
/// nothing needs it.
final resolvedInstanceProvider = Provider.autoDispose.family<PterodactylInstance, String>(
  (ref, instanceId) {
    final instance = ref.watch(instanceListControllerProvider).value?.findById(instanceId);
    if (instance == null) {
      throw StateError('No instance registered with id "$instanceId".');
    }
    return instance;
  },
);

/// The [PterodactylApiClient] scoped to a single instance, keyed by
/// [instanceId].
///
/// This is the enforcement point for instance isolation: every feature
/// that needs to talk to a Pterodactyl instance (servers today; console,
/// files, backups, ... later) goes through this provider rather than
/// building its own client. Because it is a `family` provider, Riverpod
/// gives each distinct [instanceId] its own cached instance — its own
/// [PterodactylApiClient], its own [Dio] under the hood, its own auth
/// token lookup closure bound to that specific id. There is no shared
/// mutable state a bug could leak across instances through.
///
/// `autoDispose`: a client for an instance the user has navigated away
/// from is torn down rather than kept alive for the rest of the app's
/// lifetime — recreating it is cheap (see `PterodactylApiClientFactory`).
final instanceApiClientProvider = Provider.autoDispose.family<PterodactylApiClient, String>(
  (ref, instanceId) {
    final instance = ref.watch(resolvedInstanceProvider(instanceId));
    final credentialStorage = ref.watch(credentialStorageProvider);
    final factory = ref.watch(apiClientFactoryProvider);

    return factory.createFor(
      baseUrl: instance.baseUrl,
      authTokenProvider: () async => (await credentialStorage.read(instanceId))?.apiKey,
    );
  },
);
