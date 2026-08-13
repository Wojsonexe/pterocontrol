import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/server_power_action.dart';
import 'server_list_controller.dart';
import 'servers_providers.dart';

/// Identifies one server within one instance — the family argument for
/// [ServerPowerActionController]. A plain record: structurally equal
/// records with the same fields are `==`, which is exactly what a Riverpod
/// family key needs, with no extra class required.
typedef ServerActionTarget = ({String instanceId, String serverIdentifier});

/// Tracks the in-flight/last-result state of a power action for **one**
/// server, so `ServerDetailScreen` can show a loading state, block repeat
/// taps, and surface success/error — without touching `ServerListState`
/// (which is about "the list of servers for an instance", not "is server X
/// currently being power-cycled").
///
/// Reuses the same `AsyncNotifier`/`AsyncValue` machinery as every other
/// controller in this app instead of introducing a bespoke state machine:
/// `AsyncValue.loading()` while the request is in flight,
/// `AsyncValue.data(action)` after a successful send, `AsyncValue.error`
/// on failure. `null` data means "no action attempted yet this session".
///
/// Scoped by [ServerActionTarget] (`.family`), and every request goes
/// through `serverRepositoryProvider(target.instanceId)` — the same
/// instance-scoped repository the server list already uses — so this
/// inherits the existing instance-isolation guarantees for free; it never
/// builds or holds an API client itself.
class ServerPowerActionController extends AsyncNotifier<ServerPowerAction?> {
  ServerPowerActionController(this.target);

  final ServerActionTarget target;

  @override
  Future<ServerPowerAction?> build() async => null;

  /// Sends [action]. No-op if a send is already in flight for this server
  /// — the UI also disables the buttons while busy, but this guard makes
  /// that correct even if `send` were ever called from more than one place
  /// (e.g. a future keyboard shortcut).
  ///
  /// On success, refreshes this instance's server list so whatever the
  /// Panel currently reports (administrative status, limits) stays in
  /// sync — see [ServerPowerAction] for why this does not mean the UI can
  /// show a live "now running" state yet.
  Future<void> send(ServerPowerAction action) async {
    if (state.isLoading) return;

    state = const AsyncValue.loading();
    final result = await AsyncValue.guard(() async {
      final repository = ref.read(serverRepositoryProvider(target.instanceId));
      await repository.sendPowerAction(target.serverIdentifier, action);
      return action;
    });

    // This provider is `autoDispose`: if the user navigated away from the
    // server detail screen while the request above was in flight, nothing
    // is watching this controller anymore and it may already be disposed.
    // `ref.mounted` avoids writing to `state` (and refreshing a server list
    // provider that could be in the same situation) after that happens.
    if (!ref.mounted) return;
    state = result;

    if (!result.hasError) {
      await ref.read(serverListControllerProvider(target.instanceId).notifier).refresh();
    }
  }
}

final serverPowerActionControllerProvider = AsyncNotifierProvider.autoDispose
    .family<ServerPowerActionController, ServerPowerAction?, ServerActionTarget>(
  ServerPowerActionController.new,
);
