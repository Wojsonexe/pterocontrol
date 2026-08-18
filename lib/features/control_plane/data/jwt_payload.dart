import 'dart:convert';

/// Decodes the payload segment of a JWT — no signature verification, and
/// none is needed: the backend is always the one that verifies a token
/// before acting on a request, this just needs to read the `tenantId`
/// claim the login response doesn't otherwise surface (see
/// `control_plane_auth_api.dart`). Not a general-purpose JWT library — this
/// app has no other use for one, so pulling in a dependency for ~10 lines
/// of base64url decoding would be the wrong trade.
Map<String, dynamic> decodeJwtPayload(String token) {
  final parts = token.split('.');
  if (parts.length != 3) {
    throw const FormatException('Not a JWT (expected 3 dot-separated segments)');
  }
  final normalized = base64Url.normalize(parts[1]);
  final json = utf8.decode(base64Url.decode(normalized));
  return jsonDecode(json) as Map<String, dynamic>;
}
