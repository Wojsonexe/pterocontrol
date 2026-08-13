import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pterodactyl_mobile/app/app_provider_policy.dart';
import 'package:pterodactyl_mobile/features/authentication/application/credential_storage_provider.dart';
import 'package:pterodactyl_mobile/features/authentication/domain/credential_storage.dart';
import 'package:pterodactyl_mobile/features/authentication/domain/instance_credentials.dart';
import 'package:pterodactyl_mobile/features/console/application/console_providers.dart';
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
  group('consoleRepositoryProvider — instance isolation', () {
    test('two different instances get two distinct ConsoleRepository instances', () async {
      const instanceA = PterodactylInstance(id: 'a', name: 'A', baseUrl: 'https://a.example.com');
      const instanceB = PterodactylInstance(id: 'b', name: 'B', baseUrl: 'https://b.example.com');
      final repository = _FakeInstanceRepository();
      await repository.add(instanceA);
      await repository.add(instanceB);

      final container = ProviderContainer(
        retry: noAutomaticProviderRetry,
        overrides: [
          instanceRepositoryProvider.overrideWithValue(repository),
          credentialStorageProvider.overrideWithValue(_FakeCredentialStorage()),
        ],
      );
      addTearDown(container.dispose);
      await container.read(instanceListControllerProvider.future);

      final repoA = container.read(consoleRepositoryProvider((instanceId: 'a', serverIdentifier: 'srv-1')));
      final repoB = container.read(consoleRepositoryProvider((instanceId: 'b', serverIdentifier: 'srv-1')));

      expect(
        identical(repoA, repoB),
        isFalse,
        reason: 'instance A and instance B must never share a console connection',
      );
    });

    test('the same (instanceId, serverIdentifier) target always resolves to the same cached repository', () async {
      const instance = PterodactylInstance(id: 'a', name: 'A', baseUrl: 'https://a.example.com');
      final repository = _FakeInstanceRepository();
      await repository.add(instance);

      final container = ProviderContainer(
        retry: noAutomaticProviderRetry,
        overrides: [
          instanceRepositoryProvider.overrideWithValue(repository),
          credentialStorageProvider.overrideWithValue(_FakeCredentialStorage()),
        ],
      );
      addTearDown(container.dispose);
      await container.read(instanceListControllerProvider.future);

      const target = (instanceId: 'a', serverIdentifier: 'srv-1');
      final first = container.read(consoleRepositoryProvider(target));
      final second = container.read(consoleRepositoryProvider(target));

      expect(identical(first, second), isTrue);
    });

    test('the same instance but a different server gets a distinct repository', () async {
      const instance = PterodactylInstance(id: 'a', name: 'A', baseUrl: 'https://a.example.com');
      final repository = _FakeInstanceRepository();
      await repository.add(instance);

      final container = ProviderContainer(
        retry: noAutomaticProviderRetry,
        overrides: [
          instanceRepositoryProvider.overrideWithValue(repository),
          credentialStorageProvider.overrideWithValue(_FakeCredentialStorage()),
        ],
      );
      addTearDown(container.dispose);
      await container.read(instanceListControllerProvider.future);

      final repoServer1 = container.read(consoleRepositoryProvider((instanceId: 'a', serverIdentifier: 'srv-1')));
      final repoServer2 = container.read(consoleRepositoryProvider((instanceId: 'a', serverIdentifier: 'srv-2')));

      expect(
        identical(repoServer1, repoServer2),
        isFalse,
        reason: 'two different servers on the same instance must never share a console connection',
      );
    });
  });
}
