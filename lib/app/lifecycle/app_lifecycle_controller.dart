import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Exposes the app's current [AppLifecycleState] (resumed/inactive/paused/
/// detached/hidden) as a Riverpod provider, so any controller can react to
/// foreground/background transitions without each one wiring its own
/// [WidgetsBindingObserver] — used by `ServerRuntimeSyncController` (pause
/// polling in the background, refresh immediately on resume) and by
/// `ConsoleView` (disconnect the WebSocket in the background instead of
/// letting it fight the OS to stay alive, reconnect on resume).
///
/// A single, shared observer instead of one per consumer: registering many
/// independent [WidgetsBindingObserver]s is harmless, but a single shared
/// state that every interested controller watches is simpler to reason
/// about and keeps this concern in exactly one place.
class AppLifecycleController extends Notifier<AppLifecycleState> with WidgetsBindingObserver {
  @override
  AppLifecycleState build() {
    WidgetsBinding.instance.addObserver(this);
    ref.onDispose(() => WidgetsBinding.instance.removeObserver(this));
    return WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    this.state = state;
  }
}

final appLifecycleControllerProvider = NotifierProvider<AppLifecycleController, AppLifecycleState>(
  AppLifecycleController.new,
);

/// `true` for the states in which the app is actually visible to the user
/// and it makes sense to keep a WebSocket open / a polling timer running —
/// `inactive` (e.g. a system dialog or the app-switcher overlay is
/// momentarily on top) counts as visible, since the app is not really in
/// the background yet; `paused`/`detached`/`hidden` do not.
extension AppLifecycleStateX on AppLifecycleState {
  bool get isAppVisible => this == AppLifecycleState.resumed || this == AppLifecycleState.inactive;
}
