import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/control_plane_api_client_factory.dart';
import '../data/control_plane_session_storage_impl.dart';
import '../domain/control_plane_session_storage.dart';

/// Shared [ControlPlaneApiClientFactory] — mirrors
/// `core/network/network_providers.dart`'s `apiClientFactoryProvider`.
final controlPlaneApiClientFactoryProvider = Provider<ControlPlaneApiClientFactory>((ref) {
  return const ControlPlaneApiClientFactory();
});

final controlPlaneSessionStorageProvider = Provider<ControlPlaneSessionStorage>((ref) {
  return SecureControlPlaneSessionStorage();
});
