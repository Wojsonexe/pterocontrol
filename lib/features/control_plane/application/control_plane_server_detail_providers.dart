import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/control_plane_power_action.dart';
import '../domain/control_plane_resource_usage.dart';
import 'control_plane_servers_providers.dart';

/// Live resource usage for one server — re-fetched whenever the provider is
/// (re)watched; `autoDispose` so it stops polling the moment the detail
/// screen it backs is popped.
final controlPlaneResourcesProvider =
    FutureProvider.autoDispose.family<ControlPlaneResourceUsage, String>((ref, serverId) async {
  final result = await ref.watch(controlPlaneServersApiProvider).getResources(serverId);
  return result.fold(onSuccess: (usage) => usage, onFailure: (error) => throw error);
});

/// Tracks the in-flight/last-result state of a power action for one
/// server — same shape as `features/servers/application/
/// server_power_action_controller.dart`'s `ServerPowerActionController`,
/// just keyed by a global Control Plane server id instead of a
/// `(instanceId, identifier)` pair.
class ControlPlanePowerActionController extends AsyncNotifier<ControlPlanePowerAction?> {
  ControlPlanePowerActionController(this.serverId);

  final String serverId;

  @override
  Future<ControlPlanePowerAction?> build() async => null;

  Future<void> send(ControlPlanePowerAction action) async {
    if (state.isLoading) return;

    state = const AsyncValue.loading();
    final result = await AsyncValue.guard(() async {
      final response = await ref.read(controlPlaneServersApiProvider).sendPowerAction(serverId, action);
      return response.fold(onSuccess: (_) => action, onFailure: (error) => throw error);
    });

    if (!ref.mounted) return;
    state = result;

    if (!result.hasError) {
      ref.invalidate(controlPlaneResourcesProvider(serverId));
    }
  }
}

final controlPlanePowerActionControllerProvider = AsyncNotifierProvider.autoDispose
    .family<ControlPlanePowerActionController, ControlPlanePowerAction?, String>(
  ControlPlanePowerActionController.new,
);
