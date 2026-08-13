import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../instances/application/instance_api_client_provider.dart';
import '../data/console_api.dart';
import '../data/console_repository_impl.dart';
import '../data/web_socket_channel_transport.dart';
import '../domain/console_repository.dart';
import '../domain/console_target.dart';

/// [ConsoleApi] scoped to one instance, built on that instance's
/// [instanceApiClientProvider] — same seam `ServersApi` uses.
final _consoleApiProvider = Provider.autoDispose.family<ConsoleApi, String>((ref, instanceId) {
  final client = ref.watch(instanceApiClientProvider(instanceId));
  return ConsoleApi(client);
});

/// The real [ConsoleRepository] for one `(instanceId, serverIdentifier)`
/// pair, keyed by [ConsoleTarget].
///
/// Because this is a `family` provider, every distinct target gets its own
/// [ConsoleRepositoryImpl] instance — its own [ConsoleApi] (itself bound to
/// that instance's own [instanceApiClientProvider]/`Dio`/credential
/// lookup), its own transport connector closure, its own buffer. Nothing
/// here is shared across instances or servers.
///
/// The transport connector sends the target instance's own `baseUrl` as
/// the WebSocket `Origin` header — see `WebSocketChannelTransport.connect`
/// for why. `autoDispose`: leaving the console screen tears down the
/// connection (via [ConsoleRepository.dispose], wired below) rather than
/// leaving a WebSocket open in the background.
final consoleRepositoryProvider = Provider.autoDispose.family<ConsoleRepository, ConsoleTarget>((ref, target) {
  final api = ref.watch(_consoleApiProvider(target.instanceId));
  final instance = ref.watch(resolvedInstanceProvider(target.instanceId));

  final repository = ConsoleRepositoryImpl(
    api: api,
    serverIdentifier: target.serverIdentifier,
    transportConnector: (url) => WebSocketChannelTransport.connect(url, origin: instance.baseUrl),
  );
  ref.onDispose(() => unawaited(repository.dispose()));
  return repository;
});
