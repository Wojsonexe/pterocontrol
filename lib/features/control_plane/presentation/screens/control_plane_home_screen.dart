import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/presentation/widgets/app_top_bar.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../application/control_plane_session_controller.dart';
import '../widgets/control_plane_login_form.dart';
import '../widgets/control_plane_server_list_view.dart';

/// Entry point of Control Plane mode, reachable from Settings ->
/// "Control Plane". Mirrors `RootScreen`'s own shape at a much smaller
/// scale: this is the only place in the feature that decides between the
/// login form and the logged-in server list, by watching
/// [controlPlaneSessionControllerProvider] — everything nested under it
/// (`ControlPlaneServerDetailScreen`) can assume a session already exists.
class ControlPlaneHomeScreen extends ConsumerWidget {
  const ControlPlaneHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionAsync = ref.watch(controlPlaneSessionControllerProvider);
    final session = sessionAsync.value;

    return Scaffold(
      appBar: AppTopBar(
        title: 'Control Plane',
        subtitle: session?.userEmail,
        trailing: session == null
            ? null
            : IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'Wyloguj',
                onPressed: () => ref.read(controlPlaneSessionControllerProvider.notifier).logout(),
              ),
      ),
      body: sessionAsync.isLoading
          ? const Center(child: CircularProgressIndicator())
          : session == null
              ? const SingleChildScrollView(
                  padding: EdgeInsets.all(AppSpacing.md),
                  child: ControlPlaneLoginForm(),
                )
              : const ControlPlaneServerListView(),
    );
  }
}
