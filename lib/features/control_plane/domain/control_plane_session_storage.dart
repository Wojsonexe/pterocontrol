import 'control_plane_session.dart';

/// Persists the single active [ControlPlaneSession], if any.
///
/// Unlike `features/authentication/domain/credential_storage.dart` this is
/// not keyed by an id — Control Plane mode supports exactly one logged-in
/// account at a time in this MVP slice (see IMPLEMENTATION_STATUS.md),
/// mirroring how simple a first cut of this feature should be, not a
/// design limit of the backend itself (which is genuinely multi-tenant).
abstract interface class ControlPlaneSessionStorage {
  Future<void> save(ControlPlaneSession session);

  Future<ControlPlaneSession?> read();

  Future<void> delete();
}
