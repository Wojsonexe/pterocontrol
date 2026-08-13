import 'package:flutter_test/flutter_test.dart';
import 'package:pterodactyl_mobile/features/instances/domain/instance_url_validator.dart';

void main() {
  group('InstanceUrlValidator.validate', () {
    test('rejects an empty value', () {
      expect(InstanceUrlValidator.validate(''), isNotNull);
      expect(InstanceUrlValidator.validate(null), isNotNull);
      expect(InstanceUrlValidator.validate('   '), isNotNull);
    });

    test('rejects a value without a scheme', () {
      expect(InstanceUrlValidator.validate('panel.example.com'), isNotNull);
    });

    test('rejects a non-http(s) scheme', () {
      expect(InstanceUrlValidator.validate('ftp://panel.example.com'), isNotNull);
    });

    test('accepts a well-formed https URL', () {
      expect(InstanceUrlValidator.validate('https://panel.example.com'), isNull);
    });

    test('accepts a well-formed http URL with a port', () {
      expect(InstanceUrlValidator.validate('http://192.168.1.10:8080'), isNull);
    });
  });

  group('InstanceUrlValidator.normalize', () {
    test('strips a single trailing slash', () {
      expect(InstanceUrlValidator.normalize('https://panel.example.com/'), 'https://panel.example.com');
    });

    test('trims surrounding whitespace', () {
      expect(InstanceUrlValidator.normalize('  https://panel.example.com  '), 'https://panel.example.com');
    });

    test('leaves an already-normalized URL untouched', () {
      expect(InstanceUrlValidator.normalize('https://panel.example.com'), 'https://panel.example.com');
    });
  });
}
