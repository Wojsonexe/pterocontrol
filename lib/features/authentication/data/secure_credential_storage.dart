import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/error/app_exception.dart';
import '../domain/credential_storage.dart';
import '../domain/instance_credentials.dart';

/// [CredentialStorage] backed by platform-native secure storage: Android
/// Keystore (via `flutter_secure_storage`'s default Android configuration —
/// AES-GCM data encryption with an RSA-OAEP-wrapped key held in the
/// Keystore, no biometric gate) and iOS/macOS Keychain.
///
/// Every credential is stored under its own key, namespaced by
/// [instanceId] (see [_keyFor]) — instances are isolated at the storage
/// layer itself, not just by convention in calling code: deleting one
/// instance's credential can never touch another's entry, and there is no
/// shared blob whose parsing could accidentally mix them.
///
/// No biometric gate yet — out of scope for this step (see README). Adding
/// one later (`AndroidOptions.biometric()` / an iOS accessibility option)
/// only touches this file.
class SecureCredentialStorage implements CredentialStorage {
  SecureCredentialStorage({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<void> save(String instanceId, InstanceCredentials credentials) async {
    try {
      await _storage.write(key: _keyFor(instanceId), value: credentials.apiKey);
    } catch (error) {
      // `error` (a platform exception) is kept only in `cause`, which is
      // never shown to the user or logged anywhere in this app — see
      // AppException.cause. It is deliberately not interpolated into
      // `message`.
      throw StorageException('Nie udało się bezpiecznie zapisać danych logowania.', cause: error);
    }
  }

  @override
  Future<InstanceCredentials?> read(String instanceId) async {
    try {
      final apiKey = await _storage.read(key: _keyFor(instanceId));
      return apiKey == null ? null : InstanceCredentials(apiKey: apiKey);
    } catch (error) {
      throw StorageException('Nie udało się odczytać zapisanych danych logowania.', cause: error);
    }
  }

  @override
  Future<void> delete(String instanceId) async {
    try {
      await _storage.delete(key: _keyFor(instanceId));
    } catch (error) {
      throw StorageException('Nie udało się usunąć danych logowania.', cause: error);
    }
  }

  static String _keyFor(String instanceId) => 'credentials.$instanceId';
}
