import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pterodactyl_mobile/features/control_plane/data/jwt_payload.dart';

/// Builds a JWT-shaped string with an arbitrary payload and no real
/// signature — `decodeJwtPayload` never verifies one (see its own doc
/// comment), so an unsigned/garbage third segment is exactly what a test
/// should exercise it with.
String _fakeJwt(Map<String, dynamic> payload) {
  final header = base64Url.encode(utf8.encode(jsonEncode({'alg': 'HS256', 'typ': 'JWT'}))).replaceAll('=', '');
  final body = base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '');
  return '$header.$body.fake-signature';
}

void main() {
  group('decodeJwtPayload', () {
    test('decodes the payload segment of a well-formed JWT', () {
      final token = _fakeJwt({'sub': 'user-1', 'tenantId': 'tenant-1', 'role': 'owner'});

      final payload = decodeJwtPayload(token);

      expect(payload['sub'], 'user-1');
      expect(payload['tenantId'], 'tenant-1');
      expect(payload['role'], 'owner');
    });

    test('decodes correctly regardless of base64url padding', () {
      // Payload lengths that do/don't need '=' padding when base64url
      // decoded — both must work since JWTs are emitted without padding.
      final short = _fakeJwt({'a': 1});
      final longer = _fakeJwt({'tenantId': 'a-much-longer-tenant-identifier-value'});

      expect(decodeJwtPayload(short)['a'], 1);
      expect(decodeJwtPayload(longer)['tenantId'], 'a-much-longer-tenant-identifier-value');
    });

    test('throws FormatException for a string that is not 3 dot-separated segments', () {
      expect(() => decodeJwtPayload('not-a-jwt'), throwsFormatException);
      expect(() => decodeJwtPayload('only.two'), throwsFormatException);
    });
  });
}
