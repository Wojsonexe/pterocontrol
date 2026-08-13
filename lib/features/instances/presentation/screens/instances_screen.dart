import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/app_routes.dart';
import '../../../../core/error/app_exception.dart';
import '../../../../core/presentation/widgets/error_view.dart';
import '../../../../core/theme/app_semantic_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../application/instance_list_controller.dart';
import '../../application/instance_list_state.dart';
import '../../domain/pterodactyl_instance.dart';
import '../widgets/empty_instances_view.dart';
import '../widgets/instance_tile.dart';

/// Every configured Pterodactyl panel, with connection status and a way to
/// add, switch to, or remove one.
///
/// Used in two places, both showing the exact same list/actions: as the
/// app's root (`RootScreen`, when at least one panel already exists but
/// none is active — no back button, since `Navigator` has nothing to pop
/// to there; a device with zero panels ever configured sees
/// `WelcomeScreen` instead) and as "Więcej -> Połączenia" (pushed on top
/// of the shell once a panel is already active — gets a back button
/// automatically for the same reason).
/// Switching the active panel always lands on that panel's Dashboard,
/// regardless of which of the two contexts triggered it.
class InstancesScreen extends ConsumerWidget {
  const InstancesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(instanceListControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Panele')),
      body: state.when(
        data: (data) => _InstancesBody(state: data),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => ErrorView(
          message: error is AppException ? error.message : 'Nie udało się wczytać listy instancji.',
          onRetry: () => ref.invalidate(instanceListControllerProvider),
        ),
      ),
      floatingActionButton: state.value?.instances.isNotEmpty ?? false
          ? FloatingActionButton.extended(
              onPressed: () => context.push(AppRoutes.addInstance),
              icon: const Icon(Icons.add),
              label: const Text('Dodaj instancję'),
            )
          : null,
    );
  }
}

class _InstancesBody extends ConsumerWidget {
  const _InstancesBody({required this.state});

  final InstanceListState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.instances.isEmpty) {
      return EmptyInstancesView(onAddInstance: () => context.push(AppRoutes.addInstance));
    }

    final notifier = ref.read(instanceListControllerProvider.notifier);

    return RefreshIndicator(
      onRefresh: () => ref.refresh(instanceListControllerProvider.future),
      child: ListView.builder(
        // Bottom padding clears the FloatingActionButton so the last tile
        // is never hidden behind it.
        padding: const EdgeInsets.only(top: AppSpacing.xs, bottom: AppSpacing.xxxl),
        itemCount: state.instances.length,
        itemBuilder: (context, index) {
          final instance = state.instances[index];
          return InstanceTile(
            instance: instance,
            isActive: instance.id == state.activeInstanceId,
            onTap: () {
              notifier.setActiveInstance(instance.id);
              context.go(AppRoutes.dashboard);
            },
            onAction: (action) => switch (action) {
              InstanceTileAction.checkConnection => notifier.checkConnection(instance.id),
              InstanceTileAction.delete => _confirmDelete(context, notifier, instance),
            },
          );
        },
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    InstanceListController notifier,
    PterodactylInstance instance,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Usunąć instancję?'),
        content: Text(
          'Instancja "${instance.name}" i zapisany dla niej klucz API zostaną usunięte z tego urządzenia.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Anuluj')),
          FilledButton.tonal(
            style: FilledButton.styleFrom(foregroundColor: AppSemanticColors.of(context).danger),
            autofocus: false,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Usuń'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      await notifier.removeInstance(instance.id);
    }
  }
}
