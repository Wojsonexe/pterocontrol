import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/app_routes.dart';
import '../../../../core/error/app_exception.dart';
import '../../../../core/presentation/widgets/app_card.dart';
import '../../../../core/presentation/widgets/error_view.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../application/control_plane_servers_providers.dart';
import '../../domain/control_plane_server.dart';

/// The logged-in body of Control Plane mode: the tenant's server list,
/// pull-to-refresh, tap-through to `ControlPlaneServerDetailScreen`.
class ControlPlaneServerListView extends ConsumerWidget {
  const ControlPlaneServerListView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serversAsync = ref.watch(controlPlaneServersControllerProvider);

    return serversAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => ErrorView(
        message: error is AppException ? error.message : 'Nie udało się wczytać listy serwerów.',
        onRetry: () => ref.read(controlPlaneServersControllerProvider.notifier).refresh(),
      ),
      data: (servers) {
        if (servers.isEmpty) {
          return RefreshIndicator(
            onRefresh: () => ref.read(controlPlaneServersControllerProvider.notifier).refresh(),
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              children: const [
                SizedBox(height: AppSpacing.xxl),
                Center(child: Text('Brak serwerów widocznych z tego konta.')),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () => ref.read(controlPlaneServersControllerProvider.notifier).refresh(),
          child: ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.md),
            itemCount: servers.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) => _ServerTile(server: servers[index]),
          ),
        );
      },
    );
  }
}

class _ServerTile extends StatelessWidget {
  const _ServerTile({required this.server});

  final ControlPlaneServer server;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppCard(
      onTap: () => context.push(AppRoutes.controlPlaneServerDetail(server.id)),
      child: Row(
        children: [
          Icon(Icons.dns_outlined, color: theme.colorScheme.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(server.name, style: theme.textTheme.titleMedium),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  'Node ${server.nodeId} · ${server.identifier}',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }
}
