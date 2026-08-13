import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/app_routes.dart';
import '../../../../core/error/app_exception.dart';
import '../../../../core/presentation/widgets/app_search_field.dart';
import '../../../../core/presentation/widgets/app_top_bar.dart';
import '../../../../core/presentation/widgets/error_view.dart';
import '../../../../core/presentation/widgets/fade_slide_in.dart';
import '../../../../core/presentation/widgets/filter_sheet.dart';
import '../../../../core/presentation/widgets/skeleton_box.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_surface_colors.dart';
import '../../../instances/application/instance_list_controller.dart';
import '../../application/server_list_controller.dart';
import '../../application/server_list_state.dart';
import '../../application/server_runtime_sync_controller.dart';
import '../../application/server_runtime_sync_state.dart';
import '../../domain/server.dart';
import '../widgets/empty_servers_view.dart';
import '../widgets/server_card.dart';
import '../widgets/sync_status_indicator.dart';

enum _SortMode { name, status }

enum _StatusFilter { all, active, attention }

extension on _SortMode {
  String get label => switch (this) { _SortMode.name => 'Nazwa', _SortMode.status => 'Status' };
}

extension on _StatusFilter {
  String get label => switch (this) {
        _StatusFilter.all => 'Wszystkie',
        _StatusFilter.active => 'Aktywne',
        _StatusFilter.attention => 'Wymagają uwagi',
      };
}

/// Full "Serwery" tab: search, status filter, sort, pull-to-refresh,
/// scroll-triggered pagination, skeleton loading, and honest empty/error
/// states — the primary way to browse every server on the active panel
/// (the Dashboard tab only ever shows a short preview of this same list).
/// Every [ServerCard] here reflects the same live sync data the Dashboard
/// does (`ServerRuntimeSyncController`) — this is one real-time view, not
/// a separate stale snapshot.
///
/// Search/sort/filter are client-side over whatever page(s) are already
/// loaded — the Pterodactyl Client API has no server-side search on this
/// endpoint, so a query that would only match a not-yet-loaded page won't
/// surface results until the user scrolls to load more (or clears the
/// query). This mirrors `ServerListController`'s own documented reasoning
/// for paging lazily instead of eagerly (README, "Paginacja").
class ServersScreen extends ConsumerWidget {
  const ServersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final instanceId = ref.watch(instanceListControllerProvider).value?.activeInstanceId;
    final syncStatus = instanceId == null
        ? null
        : ref.watch(serverRuntimeSyncControllerProvider(instanceId).select((s) => s.status));

    return Scaffold(
      appBar: AppTopBar(
        title: 'Serwery',
        trailing: instanceId == null
            ? null
            : SyncStatusIndicator(status: syncStatus ?? ServerSyncStatus.syncing),
      ),
      body: instanceId == null
          ? const Center(child: Text('Brak aktywnego panelu.'))
          : _ServersBody(instanceId: instanceId),
    );
  }
}

class _ServersBody extends ConsumerStatefulWidget {
  const _ServersBody({required this.instanceId});

  final String instanceId;

  @override
  ConsumerState<_ServersBody> createState() => _ServersBodyState();
}

class _ServersBodyState extends ConsumerState<_ServersBody> {
  final _searchController = TextEditingController();
  String _query = '';
  _SortMode _sortMode = _SortMode.name;
  _StatusFilter _statusFilter = _StatusFilter.all;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Server> _filterSortAndSearch(List<Server> servers) {
    final query = _query.trim().toLowerCase();
    var filtered = query.isEmpty
        ? servers
        : servers.where((s) => s.name.toLowerCase().contains(query) || s.node.toLowerCase().contains(query)).toList();

    filtered = switch (_statusFilter) {
      _StatusFilter.all => filtered,
      _StatusFilter.active => filtered.where((s) => s.status == ServerAdministrativeStatus.active).toList(),
      _StatusFilter.attention => filtered.where((s) => s.status != ServerAdministrativeStatus.active).toList(),
    };

    final sorted = [...filtered];
    switch (_sortMode) {
      case _SortMode.name:
        sorted.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      case _SortMode.status:
        sorted.sort((a, b) => a.status.index.compareTo(b.status.index));
    }
    return sorted;
  }

  Future<void> _pickSort() async {
    final picked = await showFilterSheet<_SortMode>(
      context: context,
      title: 'Sortuj według',
      selected: _sortMode,
      options: const [
        FilterOption(value: _SortMode.name, label: 'Nazwa', icon: Icons.sort_by_alpha_rounded),
        FilterOption(value: _SortMode.status, label: 'Status', icon: Icons.flag_outlined),
      ],
    );
    if (picked != null) setState(() => _sortMode = picked);
  }

  Future<void> _pickFilter() async {
    final picked = await showFilterSheet<_StatusFilter>(
      context: context,
      title: 'Filtruj status',
      selected: _statusFilter,
      options: const [
        FilterOption(value: _StatusFilter.all, label: 'Wszystkie', icon: Icons.apps_rounded),
        FilterOption(value: _StatusFilter.active, label: 'Aktywne', icon: Icons.check_circle_outline),
        FilterOption(value: _StatusFilter.attention, label: 'Wymagają uwagi', icon: Icons.error_outline),
      ],
    );
    if (picked != null) setState(() => _statusFilter = picked);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(serverListControllerProvider(widget.instanceId));
    final syncState = ref.watch(serverRuntimeSyncControllerProvider(widget.instanceId));
    final surfaces = AppSurfaceColors.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.xs),
          child: Row(
            children: [
              Expanded(
                child: AppSearchField(
                  controller: _searchController,
                  hintText: 'Szukaj serwera lub węzła…',
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              _IconToggleButton(
                icon: Icons.filter_list_rounded,
                active: _statusFilter != _StatusFilter.all,
                tooltip: 'Filtruj: ${_statusFilter.label}',
                onTap: _pickFilter,
              ),
              const SizedBox(width: AppSpacing.xxs),
              _IconToggleButton(
                icon: Icons.swap_vert_rounded,
                active: _sortMode != _SortMode.name,
                tooltip: 'Sortuj: ${_sortMode.label}',
                onTap: _pickSort,
              ),
            ],
          ),
        ),
        if (_statusFilter != _StatusFilter.all)
          Padding(
            padding: const EdgeInsets.only(left: AppSpacing.md, bottom: AppSpacing.xs),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Chip(
                label: Text('Filtr: ${_statusFilter.label}'),
                onDeleted: () => setState(() => _statusFilter = _StatusFilter.all),
                deleteIconColor: surfaces.textSecondary,
              ),
            ),
          ),
        Expanded(
          child: state.when(
            data: (data) => _ServerListView(
              instanceId: widget.instanceId,
              servers: _filterSortAndSearch(data.servers),
              rawState: data,
              hasFilters: _query.trim().isNotEmpty || _statusFilter != _StatusFilter.all,
              syncState: syncState,
            ),
            loading: () => const _ServersSkeleton(),
            error: (error, stackTrace) => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: 420,
                  child: ErrorView(
                    message: error is AppException ? error.message : 'Nie udało się wczytać listy serwerów.',
                    onRetry: () => ref.invalidate(serverListControllerProvider(widget.instanceId)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _IconToggleButton extends StatelessWidget {
  const _IconToggleButton({required this.icon, required this.active, required this.tooltip, required this.onTap});

  final IconData icon;
  final bool active;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaces = AppSurfaceColors.of(context);

    return Tooltip(
      message: tooltip,
      child: Material(
        color: active ? theme.colorScheme.primaryContainer : surfaces.surfaceActive,
        borderRadius: BorderRadius.circular(AppRadius.full),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.full),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xs),
            child: Icon(
              icon,
              size: 20,
              color: active ? theme.colorScheme.onPrimaryContainer : surfaces.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _ServerListView extends ConsumerWidget {
  const _ServerListView({
    required this.instanceId,
    required this.servers,
    required this.rawState,
    required this.hasFilters,
    required this.syncState,
  });

  final String instanceId;
  final List<Server> servers;
  final ServerListState rawState;
  final bool hasFilters;
  final ServerRuntimeSyncState syncState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(serverListControllerProvider(instanceId).notifier);

    if (rawState.servers.isEmpty) {
      return RefreshIndicator(
        onRefresh: notifier.refresh,
        child: const SingleChildScrollView(
          physics: AlwaysScrollableScrollPhysics(),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
            child: EmptyServersView(),
          ),
        ),
      );
    }

    if (servers.isEmpty && hasFilters) {
      final surfaces = AppSurfaceColors.of(context);
      return RefreshIndicator(
        onRefresh: notifier.refresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxxl, horizontal: AppSpacing.xl),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.search_off_rounded, size: 40, color: surfaces.textTertiary),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Brak serwerów pasujących do wyszukiwania/filtra.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: surfaces.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: notifier.refresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          final metrics = notification.metrics;
          if (metrics.pixels >= metrics.maxScrollExtent - 200) {
            unawaited(_loadMore(context, notifier));
          }
          return false;
        },
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xxs, AppSpacing.md, AppSpacing.xl),
          itemCount: servers.length + (rawState.isLoadingNextPage ? 1 : 0),
          itemBuilder: (context, index) {
            if (index >= servers.length) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Center(
                  child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              );
            }

            final server = servers[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: FadeSlideIn(
                index: index,
                child: ServerCard(
                  server: server,
                  runtimeState: syncState.runtimeFor(server.identifier),
                  history: syncState.historyByServer[server.identifier],
                  isRefreshing: syncState.isRefreshing(server.identifier),
                  hasRecentFailure: syncState.hasRecentFailure(server.identifier),
                  onTap: () => context.go(AppRoutes.serverDetail(server.identifier)),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _loadMore(BuildContext context, ServerListController notifier) async {
    try {
      await notifier.loadNextPage();
    } catch (error) {
      if (!context.mounted) return;
      final message = error is AppException ? error.message : 'Nie udało się wczytać kolejnych serwerów.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }
}

class _ServersSkeleton extends StatelessWidget {
  const _ServersSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        for (var i = 0; i < 5; i++)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: _ServerCardSkeleton(),
          ),
      ],
    );
  }
}

class _ServerCardSkeleton extends StatelessWidget {
  const _ServerCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppSurfaceColors.of(context).surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SkeletonBox(width: 40, height: 40, borderRadius: BorderRadius.all(Radius.circular(999))),
              SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(width: 140, height: 16),
                    SizedBox(height: AppSpacing.xxs),
                    SkeletonBox(width: 90, height: 12),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: AppSpacing.sm),
          SkeletonBox(width: 90, height: 22, borderRadius: BorderRadius.all(Radius.circular(999))),
          SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(child: SkeletonBox(height: 24)),
              SizedBox(width: AppSpacing.md),
              Expanded(child: SkeletonBox(height: 24)),
            ],
          ),
        ],
      ),
    );
  }
}
