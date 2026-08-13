import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../instances/application/instance_api_client_provider.dart';
import '../data/server_repository_impl.dart';
import '../data/servers_api.dart';
import '../domain/server_repository.dart';

/// [ServersApi] scoped to one instance, built on that instance's
/// [instanceApiClientProvider]. `autoDispose.family` for the same reason as
/// [instanceApiClientProvider]: no reason to keep it around once nothing is
/// watching it.
final _serversApiProvider = Provider.autoDispose.family<ServersApi, String>((ref, instanceId) {
  final client = ref.watch(instanceApiClientProvider(instanceId));
  return ServersApi(client);
});

/// The app-wide [ServerRepository] for a given instance.
///
/// A fresh [ServerRepositoryImpl] is created per [instanceId], wired to
/// that instance's [ServersApi] — see [ServerRepository]'s doc comment for
/// why the repository itself, not just the underlying client, is
/// instance-scoped.
final serverRepositoryProvider = Provider.autoDispose.family<ServerRepository, String>((ref, instanceId) {
  return ServerRepositoryImpl(ref.watch(_serversApiProvider(instanceId)));
});
