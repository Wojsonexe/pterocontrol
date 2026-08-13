import 'instance_credentials.dart';

/// Persists and retrieves [InstanceCredentials] for a given instance.
///
/// This is a deliberate abstraction: callers never depend on how or where
/// credentials are actually stored. Today's implementation
/// ([SecureCredentialStorage], `data/secure_credential_storage.dart`) is
/// backed by platform-native secure storage (Android Keystore / iOS
/// Keychain via `flutter_secure_storage`). Swapping it again later — e.g.
/// to add a biometric gate — only means changing
/// `credential_storage_provider.dart`; every other layer only depends on
/// this interface (see README, "Secure storage poświadczeń").
abstract interface class CredentialStorage {
  Future<void> save(String instanceId, InstanceCredentials credentials);

  Future<InstanceCredentials?> read(String instanceId);

  Future<void> delete(String instanceId);
}
