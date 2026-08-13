import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/diagnostics/perf_log.dart';
import '../../../core/error/app_exception.dart';
import '../../../core/network/network_providers.dart';
import '../../authentication/application/credential_storage_provider.dart';
import '../../authentication/domain/instance_credentials.dart';
import '../domain/instance_url_validator.dart';
import '../domain/pterodactyl_instance.dart';
import 'instance_list_state.dart';
import 'instance_providers.dart';

/// Instance Manager: owns the list of configured Pterodactyl instances, the
/// active instance, and the actions the UI can perform on them (add,
/// remove, select, check connectivity).
///
/// This is the only place in the `instances` feature allowed to talk to
/// [InstanceRepository] and `CredentialStorage` directly — widgets always
/// go through this controller, never through the repositories themselves.
class InstanceListController extends AsyncNotifier<InstanceListState> {
  InstanceListController({Uuid? idGenerator}) : _idGenerator = idGenerator ?? const Uuid();

  final Uuid _idGenerator;

  @override
  Future<InstanceListState> build() async {
    final repository = ref.read(instanceRepositoryProvider);
    final instances = await repository.getAll();
    final activeInstanceId = await repository.getActiveInstanceId();
    return InstanceListState(instances: instances, activeInstanceId: activeInstanceId);
  }

  /// Adds a new instance with the given [name]/[baseUrl], stores [apiKey]
  /// for it, and makes it the active instance if it is the first one added.
  Future<void> addInstance({
    required String name,
    required String baseUrl,
    required String apiKey,
  }) async {
    final previous = state.value ?? const InstanceListState(instances: []);
    final id = _idGenerator.v4();
    final instance = PterodactylInstance(
      id: id,
      name: name.trim(),
      baseUrl: InstanceUrlValidator.normalize(baseUrl),
    );

    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final repository = ref.read(instanceRepositoryProvider);
      final credentialStorage = ref.read(credentialStorageProvider);

      await repository.add(instance);
      await credentialStorage.save(id, InstanceCredentials(apiKey: apiKey.trim()));

      final makeActive = previous.instances.isEmpty;
      if (makeActive) {
        await repository.setActiveInstanceId(id);
      }

      return InstanceListState(
        instances: [...previous.instances, instance],
        activeInstanceId: makeActive ? id : previous.activeInstanceId,
      );
    });
  }

  /// Removes [instanceId] and its stored credentials. If it was the active
  /// instance, there is no active instance afterwards.
  Future<void> removeInstance(String instanceId) async {
    final previous = state.value;
    if (previous == null) return;

    state = await AsyncValue.guard(() async {
      final repository = ref.read(instanceRepositoryProvider);
      final credentialStorage = ref.read(credentialStorageProvider);

      await repository.remove(instanceId);
      await credentialStorage.delete(instanceId);

      return InstanceListState(
        instances: previous.instances.where((instance) => instance.id != instanceId).toList(),
        activeInstanceId: previous.activeInstanceId == instanceId ? null : previous.activeInstanceId,
      );
    });
  }

  /// Marks [instanceId] as the active instance.
  Future<void> setActiveInstance(String instanceId) async {
    final previous = state.value;
    if (previous == null || previous.findById(instanceId) == null) return;

    await ref.read(instanceRepositoryProvider).setActiveInstanceId(instanceId);
    state = AsyncValue.data(
      InstanceListState(instances: previous.instances, activeInstanceId: instanceId),
    );
  }

  /// Performs a minimal reachability check against [instanceId]'s base URL
  /// and updates its [PterodactylInstance.connectionStatus] accordingly.
  ///
  /// This intentionally does not call any Pterodactyl-specific endpoint —
  /// no endpoints are implemented yet (see README). It only proves that
  /// the generic [PterodactylApiClient] built in `core/network` can reach
  /// the configured host, which is enough to give the instance list a real
  /// (not simulated) status.
  Future<void> checkConnection(String instanceId) async {
    final current = state.value;
    final instance = current?.findById(instanceId);
    if (current == null || instance == null) return;

    _setStatus(instanceId, InstanceConnectionStatus.checking);

    final credentialStorage = ref.read(credentialStorageProvider);
    final client = ref.read(apiClientFactoryProvider).createFor(
          baseUrl: instance.baseUrl,
          authTokenProvider: () async => (await credentialStorage.read(instanceId))?.apiKey,
        );

    final result = await client.get<void>('/', parser: (_) {});
    result.fold(
      onSuccess: (_) => _setStatus(instanceId, InstanceConnectionStatus.online),
      onFailure: (error) => _setStatus(
        instanceId,
        error is UnauthorizedException || error is ForbiddenException
            ? InstanceConnectionStatus.error
            : InstanceConnectionStatus.offline,
      ),
    );
  }

  /// Tests whether [baseUrl]/[apiKey] can actually authenticate against a
  /// Pterodactyl Client API — **without** persisting anything. Used by the
  /// add-panel wizard's connection-test step, so a broken URL/key is
  /// caught before it is ever saved, instead of only surfacing on the
  /// first real use.
  ///
  /// Reuses the same [apiClientFactoryProvider] every saved instance's
  /// client is built from — this is not a second, parallel way of talking
  /// to a Pterodactyl Panel, just the existing one used before an id
  /// exists to key it by. Hits `/api/client` (not `/`, unlike
  /// [checkConnection]) so a wrong-but-reachable URL and a right URL with
  /// a wrong key are told apart (401 vs. a generic network/format error).
  ///
  /// Returns `null` on success, or the [AppException] describing why it
  /// failed.
  Future<AppException?> testConnection({required String baseUrl, required String apiKey}) async {
    final client = ref.read(apiClientFactoryProvider).createFor(
          baseUrl: baseUrl,
          authTokenProvider: () async => apiKey,
        );
    final stopwatch = Stopwatch()..start();
    final result = await client.get<void>('/api/client', parser: (_) {});
    final error = result.fold(onSuccess: (_) => null, onFailure: (error) => error);

    // Debug-only, no secrets (see `perfLog`): the connect-panel wizard's
    // own error message is deliberately generic for the user ("Nie udało
    // się połączyć") — this is what actually distinguishes "never reached
    // the panel at all" (NetworkException — DNS/refused/no OS network
    // permission) from "reached it, but got rejected" (401/403/...) while
    // debugging a report like "connect stopped working".
    perfLog(
      'ConnectPanel',
      'URL: $baseUrl | METHOD: GET /api/client | '
          'STATUS: ${error?.statusCode ?? (error == null ? 200 : 'n/a')} | '
          'ERROR TYPE: ${error == null ? 'none' : error.runtimeType} | '
          'LATENCY: ${stopwatch.elapsedMilliseconds}ms | '
          'AUTH PRESENT: ${apiKey.isNotEmpty ? 'yes' : 'no'}',
    );

    return error;
  }

  void _setStatus(String instanceId, InstanceConnectionStatus status) {
    final current = state.value;
    if (current == null) return;

    final updatedInstances = [
      for (final instance in current.instances)
        if (instance.id == instanceId) instance.copyWith(connectionStatus: status) else instance,
    ];
    state = AsyncValue.data(
      InstanceListState(instances: updatedInstances, activeInstanceId: current.activeInstanceId),
    );
  }
}

final instanceListControllerProvider =
    AsyncNotifierProvider<InstanceListController, InstanceListState>(InstanceListController.new);
