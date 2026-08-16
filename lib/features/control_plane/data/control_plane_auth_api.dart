import '../../../core/error/result.dart';
import '../domain/control_plane_session.dart';
import 'control_plane_api_client.dart';
import 'jwt_payload.dart';

/// Wraps `POST /auth/login` on `services/control-plane-api`
/// (`src/auth/auth.controller.ts` — real, not a guessed contract, this
/// backend was built in this same session).
///
/// There is deliberately no self-service "create account" call here: tenant
/// creation (`POST /tenants`) is an internal bootstrap operation gated by a
/// server-side `BOOTSTRAP_TOKEN` secret, not a public signup endpoint — see
/// `TenantsService` — so Control Plane mode in this app is login-only, the
/// same way it would be for any real multi-tenant SaaS client.
class ControlPlaneAuthApi {
  const ControlPlaneAuthApi(this._client);

  final ControlPlaneApiClient _client;

  /// Returns the new [ControlPlaneSession] (with `tenantId` decoded from
  /// the returned JWT — see `jwt_payload.dart`) on success.
  Future<Result<ControlPlaneSession>> login({
    required String baseUrl,
    required String email,
    required String password,
  }) {
    return _client.post<ControlPlaneSession>(
      '/auth/login',
      data: {'email': email, 'password': password},
      parser: (data) {
        final json = data as Map<String, dynamic>;
        final accessToken = json['accessToken'] as String;
        final user = json['user'] as Map<String, dynamic>;
        final userEmail = user['email'] as String;
        final payload = decodeJwtPayload(accessToken);
        final tenantId = payload['tenantId'] as String;
        return ControlPlaneSession(
          baseUrl: baseUrl,
          accessToken: accessToken,
          tenantId: tenantId,
          userEmail: userEmail,
        );
      },
    );
  }
}
