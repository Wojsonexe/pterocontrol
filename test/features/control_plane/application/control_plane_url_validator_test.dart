import 'package:flutter_test/flutter_test.dart';
import 'package:pterodactyl_mobile/features/control_plane/application/control_plane_url_validator.dart';

void main() {
  group('ControlPlaneUrlValidator.validate', () {
    test('rejects an empty value', () {
      expect(ControlPlaneUrlValidator.validate(''), isNotNull);
      expect(ControlPlaneUrlValidator.validate(null), isNotNull);
      expect(ControlPlaneUrlValidator.validate('   '), isNotNull);
    });

    test('rejects a value without a scheme', () {
      expect(ControlPlaneUrlValidator.validate('control-plane.example.com'), isNotNull);
    });

    test('rejects a non-http(s) scheme', () {
      expect(ControlPlaneUrlValidator.validate('ftp://control-plane.example.com'), isNotNull);
    });

    test('accepts a well-formed https URL', () {
      expect(ControlPlaneUrlValidator.validate('https://control-plane.example.com'), isNull);
    });
  });

  group('ControlPlaneUrlValidator.normalize', () {
    test('strips a single trailing slash', () {
      expect(ControlPlaneUrlValidator.normalize('https://cp.example.com/'), 'https://cp.example.com');
    });

    test('trims surrounding whitespace', () {
      expect(ControlPlaneUrlValidator.normalize('  https://cp.example.com  '), 'https://cp.example.com');
    });
  });
}
