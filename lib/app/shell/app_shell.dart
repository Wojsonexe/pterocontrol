import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/presentation/widgets/app_bottom_nav.dart';

const _destinations = [
  AppBottomNavItem(icon: Icons.grid_view_outlined, activeIcon: Icons.grid_view_rounded, label: 'Przegląd'),
  AppBottomNavItem(icon: Icons.dns_outlined, activeIcon: Icons.dns_rounded, label: 'Serwery'),
  AppBottomNavItem(icon: Icons.notifications_outlined, activeIcon: Icons.notifications_rounded, label: 'Alerty'),
  AppBottomNavItem(icon: Icons.more_horiz_rounded, activeIcon: Icons.more_horiz_rounded, label: 'Więcej'),
];

/// Persistent chrome around the four main sections of the app once an
/// instance is active: Overview / Servers / Alerts / More.
///
/// Built on go_router's [StatefulNavigationShell] (`StatefulShellRoute
/// .indexedStack` in `app_router.dart`) rather than a plain
/// `IndexedStack`/`BottomNavigationBar` hand-rolled in this widget: each
/// tab keeps its own navigation stack (so drilling into a server under
/// "Serwery", switching to "Więcej" and back returns to that same
/// server screen, not the servers list), and the Android system back
/// button already does the right thing (pop the current tab's stack,
/// then fall back to the previous tab) purely from using the framework's
/// own mechanism instead of reimplementing it. [AppBottomNav] (this app's
/// own bar, not the stock [NavigationBar]) only owns *how the four
/// destinations look*.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: AppBottomNav(
        items: _destinations,
        currentIndex: navigationShell.currentIndex,
        onSelect: (index) {
          // Tapping the already-selected tab pops that tab's stack back
          // to its root instead of doing nothing — the standard "tap
          // Home again to go Home" mobile convention.
          navigationShell.goBranch(index, initialLocation: index == navigationShell.currentIndex);
        },
      ),
    );
  }
}
