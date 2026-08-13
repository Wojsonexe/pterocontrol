import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/activity/presentation/screens/activity_screen.dart';
import '../../features/dashboard/presentation/screens/dashboard_screen.dart';
import '../../features/instances/presentation/screens/add_instance_screen.dart';
import '../../features/instances/presentation/screens/instances_screen.dart';
import '../../features/servers/presentation/screens/server_detail_screen.dart';
import '../../features/servers/presentation/screens/servers_screen.dart';
import '../../features/settings/presentation/screens/about_screen.dart';
import '../../features/settings/presentation/screens/account_settings_screen.dart';
import '../../features/settings/presentation/screens/application_settings_screen.dart';
import '../../features/settings/presentation/screens/security_settings_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../shell/app_shell.dart';
import '../shell/root_screen.dart';
import 'app_routes.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
final _dashboardNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'dashboard');
final _serversNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'servers');
final _activityNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'activity');
final _settingsNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'settings');

/// App-wide [GoRouter].
///
/// Two regions (see `app_routes.dart`):
/// - Pre-shell: [AppRoutes.root] ([RootScreen] — splash / welcome / panel
///   picker / redirect) and [AppRoutes.addInstance] (the add-panel
///   wizard, pushed as a full-screen flow from the welcome screen, the
///   picker, or Więcej -> Połączenia).
/// - The `/app` [StatefulShellRoute.indexedStack]: Overview / Servers /
///   Alerts / More, each its own navigation stack, wrapped in
///   [AppShell]'s bottom navigation bar. Only ever reachable once an
///   instance is active — [RootScreen] is the sole gate.
///
/// `ServerDetailScreen` is nested *inside* the Servers branch
/// (`/app/servers/:serverId`) rather than a sibling route — pushing into
/// it keeps the bottom nav visible only up to that push, matching how a
/// real app's "drill into a list item" screen behaves (no bottom nav on
/// top of a detail screen), while still counting as part of the Servers
/// tab's own back-stack.
final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: AppRoutes.root,
    routes: [
      GoRoute(path: AppRoutes.root, builder: (context, state) => const RootScreen()),
      GoRoute(path: AppRoutes.addInstance, builder: (context, state) => const AddInstanceScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            navigatorKey: _dashboardNavigatorKey,
            routes: [
              GoRoute(path: AppRoutes.dashboard, builder: (context, state) => const DashboardScreen()),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _serversNavigatorKey,
            routes: [
              GoRoute(
                path: AppRoutes.servers,
                builder: (context, state) => const ServersScreen(),
                routes: [
                  GoRoute(
                    path: AppRoutes.serverDetailPattern,
                    builder: (context, state) {
                      final serverId = state.pathParameters['serverId']!;
                      return ServerDetailScreen(serverId: serverId);
                    },
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _activityNavigatorKey,
            routes: [
              GoRoute(path: AppRoutes.activity, builder: (context, state) => const ActivityScreen()),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _settingsNavigatorKey,
            routes: [
              GoRoute(
                path: AppRoutes.settings,
                builder: (context, state) => const SettingsScreen(),
                routes: [
                  GoRoute(
                    path: 'connections',
                    builder: (context, state) => const InstancesScreen(),
                  ),
                  GoRoute(
                    path: 'application',
                    builder: (context, state) => const ApplicationSettingsScreen(),
                  ),
                  GoRoute(
                    path: 'account',
                    builder: (context, state) => const AccountSettingsScreen(),
                  ),
                  GoRoute(
                    path: 'security',
                    builder: (context, state) => const SecuritySettingsScreen(),
                  ),
                  GoRoute(
                    path: 'about',
                    builder: (context, state) => const AboutScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Nie znaleziono')),
      body: Center(child: Text('Nie znaleziono strony: ${state.uri}')),
    ),
  );
});
