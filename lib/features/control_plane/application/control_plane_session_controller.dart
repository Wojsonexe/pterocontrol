import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_exception.dart';
import '../data/control_plane_auth_api.dart';
import '../domain/control_plane_session.dart';
import 'control_plane_network_providers.dart';
import 'control_plane_url_validator.dart';

/// Owns the single active [ControlPlaneSession] (or lack of one) — the
/// Control Plane equivalent of `InstanceListController`, but for exactly
/// one account instead of a list (see `ControlPlaneSessionStorage`'s doc
/// comment for why).
class ControlPlaneSessionController extends AsyncNotifier<ControlPlaneSession?> {
  @override
  Future<ControlPlaneSession?> build() async {
    return ref.read(controlPlaneSessionStorageProvider).read();
  }

  /// Logs in against [baseUrl] and persists the resulting session on
  /// success. Returns the [AppException] on failure (mirroring
  /// `InstanceListController.testConnection`) rather than throwing, so the
  /// login screen can show a form-level error without going through
  /// `AsyncValue.error` (which would blank out the form itself).
  Future<AppException?> login({
    required String baseUrl,
    required String email,
    required String password,
  }) async {
    final normalizedUrl = ControlPlaneUrlValidator.normalize(baseUrl);
    final client = ref.read(controlPlaneApiClientFactoryProvider).createFor(
          baseUrl: normalizedUrl,
          // Login itself is `@Public()` server-side — no token to attach.
          authTokenProvider: () async => null,
        );
    final result = await ControlPlaneAuthApi(client).login(
      baseUrl: normalizedUrl,
      email: email.trim(),
      password: password,
    );

    return result.fold(
      onSuccess: (session) {
        state = AsyncValue.data(session);
        // Fire-and-forget from the caller's perspective: persistence
        // failing here would still leave the user logged in for the rest
        // of this app session, just not across a restart — not worth
        // failing the login flow itself over.
        unawaited(ref.read(controlPlaneSessionStorageProvider).save(session));
        return null;
      },
      onFailure: (error) => error,
    );
  }

  Future<void> logout() async {
    await ref.read(controlPlaneSessionStorageProvider).delete();
    state = const AsyncValue.data(null);
  }
}

final controlPlaneSessionControllerProvider =
    AsyncNotifierProvider<ControlPlaneSessionController, ControlPlaneSession?>(
  ControlPlaneSessionController.new,
);
