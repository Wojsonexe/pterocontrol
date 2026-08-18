/// A power signal sent through `POST /servers/:id/power` on the Control
/// Plane backend, which itself forwards it to Pterodactyl's Client API.
/// Kept as this feature's own small enum rather than importing
/// `features/servers/domain/server_power_action.dart` — the two modes are
/// deliberately independent (see `control_plane_session.dart`), so neither
/// should end up coupled to the other just to save four enum values.
enum ControlPlanePowerAction { start, stop, restart, kill }
