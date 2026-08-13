import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/lifecycle/app_lifecycle_controller.dart';
import '../../../core/diagnostics/perf_log.dart';
import '../domain/server.dart';
import '../domain/server_metrics_history.dart';
import '../domain/server_repository.dart';
import '../domain/server_runtime_state.dart';
import 'server_list_controller.dart';
import 'server_runtime_sync_state.dart';
import 'servers_providers.dart';

/// Keeps live power state + resource usage (CPU/memory/disk/network/uptime)
/// for every server currently loaded by `ServerListController(instanceId)`
/// up to date, by polling `GET .../resources` on a fixed interval — the
/// same mechanism and cadence the real Panel dashboard uses for its own
/// server rows (`ServerRow.tsx`'s `setInterval(() => getStats(), 30000)`;
/// see README's "Realtime sync" section for the full analysis of why a
/// per-row WebSocket is not how the reference client does this either).
///
/// Deliberately **not** a second independent store: this only ever *writes*
/// to `ServerListController` (via [ServerListController.refreshOne], for the
/// administrative-status half of a transitioning server) and *reads* from
/// it (the set of servers to poll) — the list itself remains the single
/// source of truth for "which servers exist and what is their admin
/// status"; this controller only adds live readings on top, keyed by the
/// same `identifier`.
///
/// `autoDispose.family<String instanceId>`: polling only runs while some
/// screen for that instance is actually watching this provider, and stops
/// the moment it isn't (screen popped, instance switched) — see
/// [_pause]/[ref.onDispose].
///
/// ## Two measured fixes for "oczekiwanie na dane" taking a long time
///
/// Both confirmed on a real device with the `perfLog` traces below before
/// changing anything (not guessed):
///
/// 1. **The "immediate" first tick used to race the server list's own
///    load and silently do nothing.** [build] fires its first [_tick]
///    synchronously, on purpose, so the user is not stuck waiting up to
///    [_pollInterval] for the very first reading. But that tick used to
///    read `serverListControllerProvider(instanceId)`'s `.value` — a
///    plain snapshot — at that exact synchronous instant, which is
///    *before* `ServerListController`'s own `GET /api/client` has
///    resolved (both providers start their work in the same widget
///    build pass; the list's HTTP round trip takes far longer than the
///    handful of microseconds between the two). `.value` was therefore
///    `null`, `_tick` silently saw an empty server list and returned,
///    and the real first sync only happened on the *next* periodic
///    timer — up to a full [_pollInterval] (30s) later. Fixed by
///    `await`ing `serverListControllerProvider(instanceId).future`
///    instead of reading a snapshot — this waits for whatever load is
///    already in flight rather than misreading "not finished yet" as
///    "nothing to sync".
/// 2. **Every server's UI update was batched behind the slowest one.**
///    Requests to `.../resources` were already dispatched in parallel
///    (`Future.wait(servers.map(_fetchOne))`), but [state] was only
///    assigned *once*, after every request had settled — so a single
///    slow or hung server delayed the UI update for every other server
///    too. Fixed by applying each server's result to [state] the moment
///    *that* server's own request resolves (see [_fetchAndApply]) —
///    a slow server now only ever delays its own card.
class ServerRuntimeSyncController extends Notifier<ServerRuntimeSyncState> {
  ServerRuntimeSyncController(this.instanceId);

  final String instanceId;

  /// Matches the reference web client's own polling interval for server
  /// resource usage (`ServerRow.tsx`), which in turn is tuned to sit just
  /// above the Panel's 20-second server-side cache on that endpoint
  /// (`ResourceUtilizationController.php`) — polling faster would just
  /// re-read the same cached value and add load for no fresher data.
  static const _pollInterval = Duration(seconds: 30);

  /// Caps each server's `ServerMetricsHistory` — 15 samples at the 30s
  /// poll interval above is ~7 minutes of trend, comfortably enough for a
  /// glanceable sparkline without growing memory over a long session.
  static const _maxHistorySamples = 15;

  Timer? _timer;
  bool _tickInFlight = false;
  DateTime? _builtAt;

  /// Last raw (cumulative) network counters seen per server, purely to
  /// compute the *next* tick's rate — deliberately not part of
  /// [ServerRuntimeSyncState]: this is bookkeeping for [_sampleFor], not
  /// something any UI reads directly.
  final Map<String, ({int rx, int tx, DateTime at})> _lastRawNetwork = {};

  ServerRepository get _repository => ref.read(serverRepositoryProvider(instanceId));

  @override
  ServerRuntimeSyncState build() {
    _builtAt = DateTime.now();
    ref.onDispose(() {
      _timer?.cancel();
      _timer = null;
    });

    // `serverListControllerProvider(instanceId)` is itself `autoDispose`,
    // and every read of it below is a one-off `ref.read` (a `_tick` is not
    // a rebuild, so it cannot `ref.watch`) — which on its own does *not*
    // keep that provider alive. Normally the list/dashboard screen watching
    // it directly covers that, but this controller must not silently rely
    // on that: an inert listener here ties this provider's keep-alive
    // lifetime to the list's for exactly as long as *this* controller is
    // itself being watched, without rebuilding this controller (and
    // resetting its accumulated `runtimeByServer`/timer) every time the
    // list changes, which a `ref.watch` here would do instead.
    ref.listen(serverListControllerProvider(instanceId), (previous, next) {});

    // Shared app-lifecycle signal (see AppLifecycleController): stop
    // polling the instant the app is backgrounded — satisfies "no
    // unnecessary REST requests" — and, on return to foreground, resume
    // *and* poll immediately rather than waiting up to 30s, so the
    // requirement "after reconnect, re-sync immediately, don't show stale
    // status" holds for the background/foreground case too.
    ref.listen(appLifecycleControllerProvider, (previous, next) {
      // Edge-triggered, not level-triggered — see ConsoleController's
      // identical guard: `resumed -> inactive` must not restart a timer
      // that was never paused.
      final wasVisible = previous?.isAppVisible ?? true;
      if (next.isAppVisible && !wasVisible) {
        _restart(immediate: true);
      } else if (!next.isAppVisible && wasVisible) {
        _pause();
      }
    });

    if (ref.read(appLifecycleControllerProvider).isAppVisible) {
      _restart(immediate: true);
    }

    return const ServerRuntimeSyncState();
  }

  void _pause() {
    _timer?.cancel();
    _timer = null;
  }

  void _restart({required bool immediate}) {
    _timer?.cancel();
    if (immediate) {
      unawaited(_tick());
    }
    _timer = Timer.periodic(_pollInterval, (_) => unawaited(_tick()));
  }

  Future<void> _tick() async {
    if (_tickInFlight || !ref.mounted) return;
    _tickInFlight = true;
    try {
      final List<Server> servers;
      try {
        // `.future`, not `ref.read(...).value` — see the class doc
        // comment, fix (1). Resolves immediately if the list already
        // has data; otherwise waits for whatever load is already in
        // flight instead of misreading "not loaded yet" as "no servers".
        final listState = await ref.read(serverListControllerProvider(instanceId).future);
        servers = listState.servers;
      } catch (_) {
        return; // List failed to load — nothing to sync yet; next tick retries.
      }
      if (!ref.mounted || servers.isEmpty) return;

      final sinceBuilt = _builtAt == null ? null : DateTime.now().difference(_builtAt!).inMilliseconds;
      perfLog(
        'RuntimeSync',
        'tick started${sinceBuilt != null ? " (+${sinceBuilt}ms since controller built)" : ""} — '
            '${servers.length} server(s)',
      );

      state = state.copyWith(
        refreshingIdentifiers: {...state.refreshingIdentifiers, for (final s in servers) s.identifier},
      );

      // Fix (2): each server applies its own result to `state` the
      // instant it arrives (see [_fetchAndApply]) — this `Future.wait`
      // only exists to know when the *whole tick* is done (for
      // `status`/`_tickInFlight`), not to gate any single server's UI
      // update on the others.
      final succeededFlags = await Future.wait(servers.map(_fetchAndApply));
      if (!ref.mounted) return;

      state = state.copyWith(status: succeededFlags.any((ok) => ok) ? ServerSyncStatus.live : ServerSyncStatus.offline);

      // `.../resources` only reports Wings' live power state, not the
      // Panel's administrative status — a server mid-install still reads
      // as "offline" there. For servers still administratively
      // transitional, also re-fetch the server itself so an
      // installing -> active (or restoring_backup -> active) flip is
      // caught within one poll cycle, without paying that extra request
      // for servers that are not transitioning. Mirrors the reference
      // client's `InstallListener.tsx` (`INSTALL_COMPLETED` ->
      // `getServer(uuid)`), triggered by the poll tick instead of a
      // per-server WebSocket event, since the list screen has none.
      for (final server in servers) {
        if (_isTransitional(server.status)) {
          unawaited(ref.read(serverListControllerProvider(instanceId).notifier).refreshOne(server.identifier));
        }
      }
    } finally {
      _tickInFlight = false;
    }
  }

  /// Fetches [server]'s resource usage and applies the result to [state]
  /// the moment it arrives (success or failure) — see fix (2) above.
  /// Returns whether the fetch succeeded, purely so [_tick] can compute
  /// this tick's overall [ServerSyncStatus] once every server is done.
  Future<bool> _fetchAndApply(Server server) async {
    final stopwatch = Stopwatch()..start();
    try {
      final runtime = await _repository.getResourceUsage(server.identifier);
      perfLog('RuntimeSync', '${server.name} resources: ${stopwatch.elapsedMilliseconds}ms');
      if (!ref.mounted) return false;
      _applyResult(server.identifier, server.name, runtime);
      return true;
    } catch (error) {
      perfLog('RuntimeSync', '${server.name} resources FAILED after ${stopwatch.elapsedMilliseconds}ms: $error');
      if (!ref.mounted) return false;
      // A failed refresh must never clear what was already known — only
      // stop showing it as "refreshing" and flag it as failed (a small
      // "nie udało się odświeżyć" caption in the UI), leaving
      // `runtimeByServer`'s last good reading exactly as it was.
      state = state.copyWith(
        refreshingIdentifiers: {...state.refreshingIdentifiers}..remove(server.identifier),
        failedIdentifiers: {...state.failedIdentifiers, server.identifier},
      );
      return false;
    }
  }

  /// Merges one server's freshly-fetched [runtime] into [state].
  ///
  /// Guarded by [ServerRuntimeState.observedAt]: a reading only replaces
  /// what's already stored if it is actually newer. This is what makes
  /// the "which source wins" policy just "the freshest reading wins" —
  /// an out-of-order REST response (network jitter let an older request
  /// resolve after a newer one) cannot clobber a fresher value, and if a
  /// WebSocket-sourced reading (`ConsoleRepositoryImpl`, which stamps the
  /// exact same `observedAt` field) is ever merged into this same state
  /// in the future, this same rule already gives it correct priority
  /// without needing a separate "source" concept.
  void _applyResult(String identifier, String serverName, ServerRuntimeState runtime) {
    final existing = state.runtimeByServer[identifier];
    final isNewer = existing?.observedAt == null ||
        runtime.observedAt == null ||
        runtime.observedAt!.isAfter(existing!.observedAt!);

    final updatedRefreshing = {...state.refreshingIdentifiers}..remove(identifier);
    final updatedFailed = {...state.failedIdentifiers}..remove(identifier);

    if (!isNewer) {
      state = state.copyWith(refreshingIdentifiers: updatedRefreshing, failedIdentifiers: updatedFailed);
      perfLog('UI', '$serverName resources resolved but a fresher reading already exists — kept the newer one');
      return;
    }

    final updatedRuntime = Map<String, ServerRuntimeState>.of(state.runtimeByServer)..[identifier] = runtime;
    var updatedHistory = state.historyByServer;
    final sample = _sampleFor(identifier, runtime);
    if (sample != null) {
      updatedHistory = Map<String, ServerMetricsHistory>.of(state.historyByServer);
      final history = updatedHistory[identifier] ?? ServerMetricsHistory.empty;
      updatedHistory[identifier] = history.appending(sample, maxLength: _maxHistorySamples);
    }

    state = state.copyWith(
      runtimeByServer: updatedRuntime,
      historyByServer: updatedHistory,
      refreshingIdentifiers: updatedRefreshing,
      failedIdentifiers: updatedFailed,
    );
    perfLog('UI', '$serverName runtime state updated (per-server, independent of other servers)');
  }

  /// Builds this tick's [MetricSample] for [identifier] from [runtime], if
  /// it actually carries a resource reading — computing the network rate
  /// against whatever raw counters were last seen for this server (see
  /// [_lastRawNetwork]), `null` on the first-ever reading for it.
  MetricSample? _sampleFor(String identifier, ServerRuntimeState runtime) {
    if (!runtime.hasResourceReading) return null;
    final observedAt = runtime.observedAt ?? DateTime.now();
    final rx = runtime.networkRxBytes ?? 0;
    final tx = runtime.networkTxBytes ?? 0;

    double? rxRate;
    double? txRate;
    final previous = _lastRawNetwork[identifier];
    if (previous != null) {
      final elapsedSeconds = observedAt.difference(previous.at).inMilliseconds / 1000;
      // A negative/zero delta (server restarted and its counters reset,
      // or a clock/ordering oddity) is not a valid rate — leave it
      // unmeasured for this tick rather than show a nonsensical negative
      // throughput.
      if (elapsedSeconds > 0 && rx >= previous.rx && tx >= previous.tx) {
        rxRate = (rx - previous.rx) / elapsedSeconds;
        txRate = (tx - previous.tx) / elapsedSeconds;
      }
    }
    _lastRawNetwork[identifier] = (rx: rx, tx: tx, at: observedAt);

    return MetricSample(
      timestamp: observedAt,
      cpuPercent: runtime.cpuAbsolutePercent ?? 0,
      memoryBytes: runtime.memoryBytes ?? 0,
      networkRxRateBytesPerSecond: rxRate,
      networkTxRateBytesPerSecond: txRate,
    );
  }

  bool _isTransitional(ServerAdministrativeStatus status) {
    return status == ServerAdministrativeStatus.installing || status == ServerAdministrativeStatus.restoringBackup;
  }
}

final serverRuntimeSyncControllerProvider =
    NotifierProvider.autoDispose.family<ServerRuntimeSyncController, ServerRuntimeSyncState, String>(
  ServerRuntimeSyncController.new,
);
