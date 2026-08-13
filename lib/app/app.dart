import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/app_theme_mode_controller.dart';
import 'router/app_router.dart';

/// Root widget: wires up Material 3 theming (light/dark, following the
/// user's persisted preference — see [AppThemeModeController], Ustawienia
/// -> Wygląd) and the app's router.
class PterodactylMobileApp extends ConsumerWidget {
  const PterodactylMobileApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(appThemeModeControllerProvider);

    return MaterialApp.router(
      title: 'Pterodactyl Mobile',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
