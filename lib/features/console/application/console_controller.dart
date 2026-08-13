import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/lifecycle/app_lifecycle_controller.dart';
import '../domain/console_repository.dart';
import '../domain/console_target.dart';
import 'console_providers.dart';
import 'console_state.dart';

/// Drives one server's console for the UI: connects on [build], turns
/// [ConsoleRepository]'s three streams into a single [ConsoleState], and
/// offers [sendCommand]/[reconnect]/[disconnect] as the UI's only way to
/// affect the connection.
///
/// Scoped by [ConsoleTarget] (`.family`), same shape as
/// `ServerPowerActionController`. `autoDispose`: leaving the console
/// screen disposes this controller, which — because [build] is the only
/// watcher of [consoleRepositoryProvider] — cascades into disposing the
/// repository and closing the WebSocket. No explicit teardown call is
/// needed here beyond cancelling the stream subscriptions.
class ConsoleController extends AsyncNotifier<ConsoleState> {
  ConsoleController(this.target);

  final ConsoleTarget target;

  ConsoleRepository get _repository => ref.read(consoleRepositoryProvider(target));

  @override
  Future<ConsoleState> build() async {
    final repository = ref.watch(consoleRepositoryProvider(target));

    // Subscribe *before* connecting — ConsoleRepository's streams only
    // emit future changes, so subscribing after connect() could miss the
    // very first "connecting"/"connected" transition.
    final subscriptions = [
      repository.connectionState.listen((value) => _update((s) => s.copyWith(connectionState: value))),
      repository.runtimeState.listen((value) => _update((s) => s.copyWith(runtimeState: value))),
      repository.events.listen((value) => _update((s) => s.copyWith(events: value))),
    ];
    ref.onDispose(() {
      for (final subscription in subscriptions) {
        unawaited(subscription.cancel());
      }
    });

    // A backgrounded app has no visible console to keep live, and Wings
    // will eventually kill an idle-but-unread connection anyway — closing
    // it proactively is one fewer socket the OS has to fight to keep
    // alive while suspended, and avoids reconnect-storming a Wings node
    // for a screen nobody is looking at. On return to the foreground,
    // reconnect immediately (fresh token, fresh transport) rather than
    // showing whatever was last on screen — satisfies the same
    // "re-sync immediately after coming back" requirement
    // `ServerRuntimeSyncController` applies to the list/dashboard screens.
    ref.listen(appLifecycleControllerProvider, (previous, next) {
      // Edge-triggered, not level-triggered: `resumed -> inactive` (e.g. a
      // system dialog briefly on top) is still "visible" both before and
      // after, and must not reconnect a socket that was never dropped.
      final wasVisible = previous?.isAppVisible ?? true;
      if (next.isAppVisible && !wasVisible) {
        unawaited(repository.connect());
      } else if (!next.isAppVisible && wasVisible) {
        unawaited(repository.disconnect());
      }
    });

    unawaited(repository.connect());

    return ConsoleState.initial;
  }

  void _update(ConsoleState Function(ConsoleState) transform) {
    // `ref.mounted` matters here: repository streams are driven by
    // WebSocket/timer callbacks that can fire after this controller (and
    // its `autoDispose` repository) have already been torn down — e.g. a
    // frame in flight when the user navigates away.
    if (!ref.mounted) return;
    final current = state.value ?? ConsoleState.initial;
    state = AsyncValue.data(transform(current));
  }

  /// Sends a command to the server's console. Behind a dedicated method
  /// (rather than exposing the repository) so the UI never depends on
  /// [ConsoleRepository] directly, and so this is the one place command
  /// input can grow more behavior (e.g. history) later without touching
  /// the UI.
  void sendCommand(String command) => _repository.sendCommand(command);

  /// Manually retries after a stopped connection (e.g. after a fatal
  /// `jwt error` or a suspended-server close code, both of which stop
  /// automatic reconnection). No-op if already connected/connecting.
  Future<void> reconnect() => _repository.connect();

  /// Intentionally closes the connection; no automatic reconnect follows
  /// unless [reconnect] is called.
  Future<void> disconnect() => _repository.disconnect();
}

final consoleControllerProvider =
    AsyncNotifierProvider.autoDispose.family<ConsoleController, ConsoleState, ConsoleTarget>(
  ConsoleController.new,
);
