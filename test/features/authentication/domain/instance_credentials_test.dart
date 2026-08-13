import 'package:flutter_test/flutter_test.dart';
import 'package:pterodactyl_mobile/features/authentication/domain/instance_credentials.dart';

void main() {
  group('InstanceCredentials', () {
    test('toString() does not include the api key', () {
      const credentials = InstanceCredentials(apiKey: 'super-secret-value');

      expect(credentials.toString(), isNot(contains('super-secret-value')));
    });
  });
}
