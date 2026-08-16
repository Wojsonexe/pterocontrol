import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/error/app_exception.dart';
import '../domain/control_plane_session.dart';
import '../domain/control_plane_session_storage.dart';

/// [ControlPlaneSessionStorage] backed by platform-native secure storage —
/// same mechanism and security posture as
/// `features/authentication/data/secure_credential_storage.dart`, just a
/// single fixed key instead of one per instance id (see that interface's
/// doc comment for why).
class SecureControlPlaneSessionStorage implements ControlPlaneSessionStorage {
  SecureControlPlaneSessionStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'control_plane.session';

  final FlutterSecureStorage _storage;

  @override
  Future<void> save(ControlPlaneSession session) async {
    try {
      final json = jsonEncode({
        'baseUrl': session.baseUrl,
        'accessToken': session.accessToken,
        'tenantId': session.tenantId,
        'userEmail': session.userEmail,
      });
      await _storage.write(key: _key, value: json);
    } catch (error) {
      throw StorageException('Nie udało się bezpiecznie zapisać sesji Control Plane.', cause: error);
    }
  }

  @override
  Future<ControlPlaneSession?> read() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null) return null;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return ControlPlaneSession(
        baseUrl: json['baseUrl'] as String,
        accessToken: json['accessToken'] as String,
        tenantId: json['tenantId'] as String,
        userEmail: json['userEmail'] as String,
      );
    } catch (error) {
      throw StorageException('Nie udało się odczytać zapisanej sesji Control Plane.', cause: error);
    }
  }

  @override
  Future<void> delete() async {
    try {
      await _storage.delete(key: _key);
    } catch (error) {
      throw StorageException('Nie udało się usunąć sesji Control Plane.', cause: error);
    }
  }
}
