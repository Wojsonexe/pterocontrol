import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/control_plane_servers_api.dart';
import '../domain/control_plane_server.dart';
import 'control_plane_network_providers.dart';
import 'control_plane_session_controller.dart';

/// Builds a [ControlPlaneServersApi] authenticated with the current
/// session's bearer token.
///
/// Only ever read from providers that are only alive while a session
/// exists (`controlPlaneServersControllerProvider` and friends, watched
/// from screens nested under the logged-in part of Control Plane mode's
/// small flow — see `control_plane_home_screen.dart`) — the same
/// "screens under here can assume X already exists" contract
/// `RootScreen`/`ServersModule` use elsewhere in this app, just scoped to
/// this feature instead of the whole `/app` shell.
final controlPlaneServersApiProvider = Provider<ControlPlaneServersApi>((ref) {
  final session = ref.watch(controlPlaneSessionControllerProvider).value;
  if (session == null) {
    throw StateError('controlPlaneServersApiProvider read without an active Control Plane session');
  }
  final client = ref.read(controlPlaneApiClientFactoryProvider).createFor(
        baseUrl: session.baseUrl,
        authTokenProvider: () async => session.accessToken,
      );
  return ControlPlaneServersApi(client);
});

/// Server list for the current session's tenant.
class ControlPlaneServersController extends AsyncNotifier<List<ControlPlaneServer>> {
  @override
  Future<List<ControlPlaneServer>> build() async {
    final result = await ref.watch(controlPlaneServersApiProvider).list();
    return result.fold(onSuccess: (servers) => servers, onFailure: (error) => throw error);
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final result = await ref.read(controlPlaneServersApiProvider).list();
      return result.fold(onSuccess: (servers) => servers, onFailure: (error) => throw error);
    });
  }
}

final controlPlaneServersControllerProvider =
    AsyncNotifierProvider<ControlPlaneServersController, List<ControlPlaneServer>>(
  ControlPlaneServersController.new,
);
