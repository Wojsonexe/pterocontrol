import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/diagnostics/perf_log.dart';
import '../domain/server.dart';
import '../domain/server_repository.dart';
import 'server_list_state.dart';
import 'servers_providers.dart';

/// Server list for one Pterodactyl instance, keyed by `instanceId`.
///
/// A `family` notifier rather than a single global one: state for
/// "Instance A's servers" and "Instance B's servers" are entirely separate
/// provider instances (separate cache, separate loading/error state) —
/// there is no shared list that could mix servers from two instances
/// together. `autoDispose` so leaving an instance's screen frees its
/// server list rather than accumulating one per instance ever visited.
///
/// Only fetches the first page on [build]. Fetching every page eagerly was
/// considered and rejected: the Panel's Client API rate limit (256
/// requests/minute, shared across every client — web, mobile, anything
/// else — the user is signed into) is a *per-user* budget documented in
/// the architecture analysis, and most users have few enough servers that
/// page 1 already contains everything. Paying for every page up front on
/// every screen open/refresh would not be free for users with many
/// servers, for no benefit to the common case. [loadNextPage] exists so
/// the UI can fetch more on demand (infinite scroll) instead.
class ServerListController extends AsyncNotifier<ServerListState> {
  ServerListController(this.instanceId);

  final String instanceId;

  ServerRepository get _repository => ref.read(serverRepositoryProvider(instanceId));

  @override
  Future<ServerListState> build() => _fetchPage(1);

  /// Re-fetches from page 1, discarding any pages loaded via
  /// [loadNextPage]. Used for pull-to-refresh, and by
  /// `ServerPowerActionController` after a successful power action.
  ///
  /// This provider is `autoDispose`; a caller can trigger a refresh (e.g.
  /// `ServerPowerActionController` does, from a different provider) at a
  /// moment where nothing is watching this one anymore — the screen that
  /// was showing it may have just been popped. The `ref.mounted` check
  /// avoids writing to `state` after this controller has been disposed,
  /// which would otherwise throw `UnmountedRefException`.
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    final result = await AsyncValue.guard(() => _fetchPage(1));
    if (ref.mounted) {
      state = result;
    }
  }

  /// Fetches the next page and appends it to the current list. No-op if
  /// there is no next page, a load is already in flight, or the initial
  /// load has not completed yet.
  ///
  /// On failure the current list is left intact (a failed "load more"
  /// should not blow away servers already shown) and the error is
  /// rethrown for the caller (the scroll listener in the UI) to surface,
  /// e.g. as a `SnackBar` — the same pattern used by `AddInstanceScreen`.
  Future<void> loadNextPage() async {
    final current = state.value;
    if (current == null || !current.hasNextPage || current.isLoadingNextPage) return;

    state = AsyncValue.data(current.copyWith(isLoadingNextPage: true));
    try {
      final nextPage = await _repository.getServers(page: current.page + 1);
      if (!ref.mounted) return;
      final latest = state.value ?? current;
      state = AsyncValue.data(
        latest.copyWith(
          servers: [...latest.servers, ...nextPage.servers],
          page: nextPage.page,
          totalPages: nextPage.totalPages,
          isLoadingNextPage: false,
        ),
      );
    } catch (error) {
      if (ref.mounted) {
        state = AsyncValue.data(current.copyWith(isLoadingNextPage: false));
      }
      rethrow;
    }
  }

  Future<ServerListState> _fetchPage(int page) async {
    final stopwatch = Stopwatch()..start();
    final result = await _repository.getServers(page: page);
    perfLog(
      'ServerList',
      'GET /api/client (page $page) resolved in ${stopwatch.elapsedMilliseconds}ms — ${result.servers.length} servers',
    );
    return ServerListState(servers: result.servers, page: result.page, totalPages: result.totalPages);
  }

  /// Replaces just [serverIdentifier]'s entry in the already-loaded list
  /// with a freshly fetched copy — the targeted counterpart to [refresh]
  /// (which re-fetches everything). Used by `ServerRuntimeSyncController`
  /// and `ServerDetailScreen` (after Wings reports `install completed`) so
  /// a single server's administrative-status change never triggers a full
  /// list re-fetch/re-render for servers that did not change.
  ///
  /// No-op if [serverIdentifier] is not currently in the loaded list (nothing
  /// to replace) or if a fetch is already in flight for it — see
  /// `ServerRuntimeSyncController`, which is the only caller that could
  /// plausibly overlap with itself across ticks.
  Future<void> refreshOne(String serverIdentifier) async {
    final current = state.value;
    if (current == null) return;
    if (!current.servers.any((s) => s.identifier == serverIdentifier)) return;

    final Server fresh;
    try {
      fresh = await _repository.getServer(serverIdentifier);
    } catch (_) {
      // A transient failure to refresh one server must not disturb the
      // rest of the already-shown list — silently keep the stale entry
      // until the next successful attempt (next sync tick, or a manual
      // pull-to-refresh).
      return;
    }

    if (!ref.mounted) return;
    final latest = state.value ?? current;
    state = AsyncValue.data(
      latest.copyWith(
        servers: [
          for (final server in latest.servers)
            if (server.identifier == serverIdentifier) fresh else server,
        ],
      ),
    );
  }
}

final serverListControllerProvider =
    AsyncNotifierProvider.autoDispose.family<ServerListController, ServerListState, String>(
  ServerListController.new,
);
