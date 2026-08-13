import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/secure_credential_storage.dart';
import '../domain/credential_storage.dart';

/// The app-wide [CredentialStorage].
///
/// Backed by [SecureCredentialStorage] (Android Keystore / iOS Keychain via
/// `flutter_secure_storage`). This is the only place that needs to change
/// if the implementation is swapped again later (e.g. to add a biometric
/// gate) — every other layer only depends on the [CredentialStorage]
/// interface.
final credentialStorageProvider = Provider<CredentialStorage>((ref) {
  return SecureCredentialStorage();
});
