/// Centralized route paths, so screens and navigation calls never
/// hand-write a path string more than once.
///
/// Two regions: pre-shell (welcome screen, panel picker, and the
/// add-panel wizard, all reachable before/outside the main bottom-nav
/// shell) and `/app/...` (the [StatefulShellRoute] — Przegląd/Serwery/
/// Alerty/Więcej, i.e. Overview/Servers/Alerts/More — which only ever
/// mounts once an instance is active; see `app_router.dart` and
/// `RootScreen`). Route path segments below (`dashboard`, `activity`,
/// `settings`) are internal identifiers and intentionally not renamed
/// alongside the user-facing tab labels — renaming them would only add
/// churn/route-migration risk for zero user-visible benefit.
abstract final class AppRoutes {
  /// Root: decides between a splash frame, the panel picker, or an
  /// immediate redirect into [dashboard] — see `RootScreen`.
  static const root = '/';

  static const addInstance = '/instances/add';

  static const dashboard = '/app/dashboard';

  static const servers = '/app/servers';

  /// Path template registered with go_router, nested under [servers].
  static const serverDetailPattern = ':serverId';

  /// Concrete path for navigating to a specific server within the active
  /// instance (instance is implicit — see `RootScreen`/`AppShell`, the
  /// whole `/app` shell only exists once one instance is active).
  static String serverDetail(String serverId) => '$servers/$serverId';

  static const activity = '/app/activity';

  static const settings = '/app/settings';
  static const settingsConnections = '/app/settings/connections';
  static const settingsApplication = '/app/settings/application';
  static const settingsAccount = '/app/settings/account';
  static const settingsSecurity = '/app/settings/security';
  static const settingsAbout = '/app/settings/about';

  /// Control Plane mode (`features/control_plane`) — a separate, parallel
  /// flow from the Pterodactyl-direct panels above, reachable from
  /// Settings but not part of the `/app` shell's per-instance assumptions.
  /// See IMPLEMENTATION_STATUS.md, "Flutter — tryb Control Plane".
  static const settingsControlPlane = '/app/settings/control-plane';

  /// Path template registered with go_router, nested under
  /// [settingsControlPlane].
  static const controlPlaneServerDetailPattern = 'servers/:serverId';

  static String controlPlaneServerDetail(String serverId) =>
      '$settingsControlPlane/servers/$serverId';
}
