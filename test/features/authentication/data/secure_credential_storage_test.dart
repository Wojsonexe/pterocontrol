import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pterodactyl_mobile/core/error/app_exception.dart';
import 'package:pterodactyl_mobile/features/authentication/data/secure_credential_storage.dart';
import 'package:pterodactyl_mobile/features/authentication/domain/instance_credentials.dart';

/// Fault-injecting `FlutterSecureStoragePlatform` used to verify
/// [SecureCredentialStorage]'s error handling without needing a real
/// Keystore/Keychain (unit tests have no platform channels).
class _ThrowingSecureStoragePlatform extends FlutterSecureStoragePlatform {
  @override
  Future<bool> containsKey({required String key, required Map<String, String> options}) =>
      throw Exception('platform failure');

  @override
  Future<void> delete({required String key, required Map<String, String> options}) =>
      throw Exception('platform failure');

  @override
  Future<void> deleteAll({required Map<String, String> options}) => throw Exception('platform failure');

  @override
  Future<String?> read({required String key, required Map<String, String> options}) =>
      throw Exception('platform failure');

  @override
  Future<Map<String, String>> readAll({required Map<String, String> options}) =>
      throw Exception('platform failure');

  @override
  Future<void> write({required String key, required String value, required Map<String, String> options}) =>
      throw Exception('platform failure');
}

SecureCredentialStorage _build() {
  // Ships with flutter_secure_storage specifically for this: swaps
  // FlutterSecureStoragePlatform.instance for an in-memory fake, the same
  // technique SharedPreferences.setMockInitialValues uses. This exercises
  // the real SecureCredentialStorage code (key construction, isolation,
  // error mapping) — not a hand-rolled, unrelated CredentialStorage fake.
  FlutterSecureStorage.setMockInitialValues({});
  return SecureCredentialStorage();
}

void main() {
  group('SecureCredentialStorage', () {
    test('read returns null when nothing was saved for the instance', () async {
      final storage = _build();

      expect(await storage.read('instance-a'), isNull);
    });

    test('save then read round-trips the API key', () async {
      final storage = _build();
      await storage.save('instance-a', const InstanceCredentials(apiKey: 'ptlc_secret_a'));

      final result = await storage.read('instance-a');

      expect(result?.apiKey, 'ptlc_secret_a');
    });

    test('save overwrites a previously saved credential for the same instance', () async {
      final storage = _build();
      await storage.save('instance-a', const InstanceCredentials(apiKey: 'old'));
      await storage.save('instance-a', const InstanceCredentials(apiKey: 'new'));

      expect((await storage.read('instance-a'))?.apiKey, 'new');
    });

    test('credentials are isolated per instanceId', () async {
      final storage = _build();
      await storage.save('instance-a', const InstanceCredentials(apiKey: 'secret-a'));
      await storage.save('instance-b', const InstanceCredentials(apiKey: 'secret-b'));

      expect((await storage.read('instance-a'))?.apiKey, 'secret-a');
      expect((await storage.read('instance-b'))?.apiKey, 'secret-b');
    });

    test("delete removes only the targeted instance's credential", () async {
      final storage = _build();
      await storage.save('instance-a', const InstanceCredentials(apiKey: 'secret-a'));
      await storage.save('instance-b', const InstanceCredentials(apiKey: 'secret-b'));

      await storage.delete('instance-a');

      expect(await storage.read('instance-a'), isNull);
      expect((await storage.read('instance-b'))?.apiKey, 'secret-b');
    });

    test('delete on an instance with no saved credential does not throw', () async {
      final storage = _build();

      await expectLater(storage.delete('does-not-exist'), completes);
    });

    test('a platform write failure is surfaced as StorageException', () async {
      FlutterSecureStoragePlatform.instance = _ThrowingSecureStoragePlatform();
      final storage = SecureCredentialStorage();

      await expectLater(
        storage.save('instance-a', const InstanceCredentials(apiKey: 'secret')),
        throwsA(isA<StorageException>()),
      );
    });

    test('a platform read failure is surfaced as StorageException', () async {
      FlutterSecureStoragePlatform.instance = _ThrowingSecureStoragePlatform();
      final storage = SecureCredentialStorage();

      await expectLater(storage.read('instance-a'), throwsA(isA<StorageException>()));
    });

    test('a platform delete failure is surfaced as StorageException', () async {
      FlutterSecureStoragePlatform.instance = _ThrowingSecureStoragePlatform();
      final storage = SecureCredentialStorage();

      await expectLater(storage.delete('instance-a'), throwsA(isA<StorageException>()));
    });

    test('a failed save never leaks the api key into the thrown exception', () async {
      FlutterSecureStoragePlatform.instance = _ThrowingSecureStoragePlatform();
      final storage = SecureCredentialStorage();

      try {
        await storage.save('instance-a', const InstanceCredentials(apiKey: 'super-secret-value'));
        fail('expected a StorageException');
      } on StorageException catch (error) {
        expect(error.message, isNot(contains('super-secret-value')));
        expect(error.toString(), isNot(contains('super-secret-value')));
      }
    });
  });
}
