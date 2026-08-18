import 'package:meta/meta.dart';

/// An authenticated session against a Pterocontrol Control Plane backend
/// (`services/control-plane-api` in this repo) — a different product from
/// the Pterodactyl-direct panels the rest of this app manages (see
/// `features/instances`). Deliberately not modeled as a
/// [PterodactylInstance]: Control Plane is multi-tenant, authenticates with
/// a short-lived JWT rather than a long-lived API key, and identifies
/// servers by a global id rather than a per-panel one — see
/// IMPLEMENTATION_STATUS.md ("Flutter — tryb Control Plane") for why this
/// is a separate, parallel feature rather than a new kind of instance.
///
/// Today's backend has no refresh-token endpoint, so [accessToken] simply
/// expires (15 minutes server-side as of this writing) and the user has to
/// log in again — [ControlPlaneApiClient] surfaces that as an
/// [UnauthorizedException] like any other rejected request, there is no
/// silent-refresh machinery to build here yet.
@immutable
class ControlPlaneSession {
  const ControlPlaneSession({
    required this.baseUrl,
    required this.accessToken,
    required this.tenantId,
    required this.userEmail,
  });

  /// Normalized (no trailing slash) base URL of the Control Plane API,
  /// e.g. `https://control-plane.example.com`.
  final String baseUrl;

  final String accessToken;

  /// Decoded from the JWT payload's `tenantId` claim at login time — the
  /// backend does not return it as a separate field in the login response.
  final String tenantId;

  final String userEmail;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ControlPlaneSession &&
        other.baseUrl == baseUrl &&
        other.accessToken == accessToken &&
        other.tenantId == tenantId &&
        other.userEmail == userEmail;
  }

  @override
  int get hashCode => Object.hash(baseUrl, accessToken, tenantId, userEmail);
}
