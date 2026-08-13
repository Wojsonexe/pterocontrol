import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/error/app_exception.dart';
import '../../core/presentation/widgets/error_view.dart';
import '../../features/instances/application/instance_list_controller.dart';
import '../../features/instances/presentation/screens/instances_screen.dart';
import '../router/app_routes.dart';
import 'splash_screen.dart';
import 'welcome_screen.dart';

/// Entry point of the app: decides what the user sees before any
/// instance is active.
///
/// - Still loading the locally stored panel list -> [SplashScreen].
/// - No panel has ever been configured on this device -> [WelcomeScreen]
///   (introduces the product before asking for a URL/API key — a brand
///   new user must never land on the picker cold).
/// - At least one panel exists, but none is active (the previously
///   active one was removed, or the user has several and needs to pick)
///   -> [InstancesScreen], the panel picker.
/// - An active instance already exists (the common case for a returning
///   user) -> nothing to show here at all; immediately hands off to
///   [AppRoutes.dashboard], which mounts the bottom-nav shell.
///
/// This is the only place in the app that makes that branching decision —
/// every screen inside `/app/...` can assume an active instance already
/// exists.
class RootScreen extends ConsumerWidget {
  const RootScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(instanceListControllerProvider);

    return state.when(
      data: (data) {
        if (data.activeInstanceId != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) context.go(AppRoutes.dashboard);
          });
          return const SplashScreen();
        }
        if (data.instances.isEmpty) return const WelcomeScreen();
        return const InstancesScreen();
      },
      loading: () => const SplashScreen(),
      error: (error, stackTrace) => Scaffold(
        appBar: AppBar(title: const Text('Pterodactyl Mobile')),
        body: ErrorView(
          message: error is AppException ? error.message : 'Nie udało się wczytać zapisanych paneli.',
          onRetry: () => ref.invalidate(instanceListControllerProvider),
        ),
      ),
    );
  }
}
