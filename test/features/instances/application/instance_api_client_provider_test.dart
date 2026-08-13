import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pterodactyl_mobile/app/app_provider_policy.dart';
import 'package:pterodactyl_mobile/features/authentication/application/credential_storage_provider.dart';
import 'package:pterodactyl_mobile/features/authentication/domain/credential_storage.dart';
import 'package:pterodactyl_mobile/features/authentication/domain/instance_credentials.dart';
import 'package:pterodactyl_mobile/features/instances/application/instance_api_client_provider.dart';
import 'package:pterodactyl_mobile/features/instances/application/instance_list_controller.dart';
import 'package:pterodactyl_mobile/features/instances/application/instance_providers.dart';
import 'package:pterodactyl_mobile/features/instances/domain/instance_repository.dart';
import 'package:pterodactyl_mobile/features/instances/domain/pterodactyl_instance.dart';

class _FakeInstanceRepository implements InstanceRepository {
  final Map<String, PterodactylInstance> _instances = {};
  String? _activeId;

  @override
  Future<List<PterodactylInstance>> getAll() async => _instances.values.toList();

  @override
  Future<void> add(PterodactylInstance instance) async => _instances[instance.id] = instance;

  @override
  Future<void> update(PterodactylInstance instance) async => _instances[instance.id] = instance;

  @override
  Future<void> remove(String instanceId) async => _instances.remove(instanceId);

  @override
  Future<String?> getActiveInstanceId() async => _activeId;

  @override
  Future<void> setActiveInstanceId(String? instanceId) async => _activeId = instanceId;
}

class _FakeCredentialStorage implements CredentialStorage {
  final Map<String, InstanceCredentials> _store = {};

  @override
  Future<void> save(String instanceId, InstanceCredentials credentials) async => _store[instanceId] = credentials;

  @override
  Future<InstanceCredentials?> read(String instanceId) async => _store[instanceId];

  @override
  Future<void> delete(String instanceId) async => _store.remove(instanceId);
}

void main() {
  group('instanceApiClientProvider (instance scoping)', () {
    test('builds a distinct client per instance, each pointed at its own baseUrl', () async {
      const instanceA = PterodactylInstance(id: 'a', name: 'A', baseUrl: 'https://a.example.com');
      const instanceB = PterodactylInstance(id: 'b', name: 'B', baseUrl: 'https://b.example.com');

      final repository = _FakeInstanceRepository();
      await repository.add(instanceA);
      await repository.add(instanceB);

      final credentialStorage = _FakeCredentialStorage();
      await credentialStorage.save('a', const InstanceCredentials(apiKey: 'token-a'));
      await credentialStorage.save('b', const InstanceCredentials(apiKey: 'token-b'));

      final container = ProviderContainer(
        retry: noAutomaticProviderRetry,
        overrides: [
          instanceRepositoryProvider.overrideWithValue(repository),
          credentialStorageProvider.overrideWithValue(credentialStorage),
        ],
      );
      addTearDown(container.dispose);
      await container.read(instanceListControllerProvider.future);

      final clientA = container.read(instanceApiClientProvider('a'));
      final clientB = container.read(instanceApiClientProvider('b'));

      expect(clientA.baseUrl, 'https://a.example.com');
      expect(clientB.baseUrl, 'https://b.example.com');
      expect(
        identical(clientA, clientB),
        isFalse,
        reason: 'instance A and instance B must never share a client instance',
      );
    });

    test('throws for an instance id that is not registered, instead of silently returning some other client', () async {
      final container = ProviderContainer(
        retry: noAutomaticProviderRetry,
        overrides: [
          instanceRepositoryProvider.overrideWithValue(_FakeInstanceRepository()),
          credentialStorageProvider.overrideWithValue(_FakeCredentialStorage()),
        ],
      );
      addTearDown(container.dispose);
      await container.read(instanceListControllerProvider.future);

      // Riverpod wraps the thrown StateError in a ProviderException when a
      // failed provider is read again — match on the underlying message
      // rather than the exact exception type.
      expect(
        () => container.read(instanceApiClientProvider('does-not-exist')),
        throwsA(predicate<Object>((e) => e.toString().contains('No instance registered with id "does-not-exist"'))),
      );
    });
  });
}
