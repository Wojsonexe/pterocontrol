import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pterodactyl_mobile/app/app_provider_policy.dart';
import 'package:pterodactyl_mobile/core/error/app_exception.dart';
import 'package:pterodactyl_mobile/core/network/api_client_config.dart';
import 'package:pterodactyl_mobile/core/network/api_client_factory.dart';
import 'package:pterodactyl_mobile/core/network/network_providers.dart';
import 'package:pterodactyl_mobile/features/authentication/application/credential_storage_provider.dart';
import 'package:pterodactyl_mobile/features/authentication/domain/credential_storage.dart';
import 'package:pterodactyl_mobile/features/authentication/domain/instance_credentials.dart';
import 'package:pterodactyl_mobile/features/instances/application/instance_list_controller.dart';
import 'package:pterodactyl_mobile/features/instances/application/instance_providers.dart';
import 'package:pterodactyl_mobile/features/instances/domain/instance_repository.dart';
import 'package:pterodactyl_mobile/features/instances/domain/pterodactyl_instance.dart';

const _instanceA = PterodactylInstance(id: 'a', name: 'Instance A', baseUrl: 'https://a.example.com');

class _FakeInstanceRepository implements InstanceRepository {
  final Map<String, PterodactylInstance> _instances = {};
  String? _activeId;

  @override
  Future<List<PterodactylInstance>> getAll() async => _instances.values.toList(growable: false);

  @override
  Future<void> add(PterodactylInstance instance) async {
    if (_instances.containsKey(instance.id)) {
      throw const StorageException('duplicate');
    }
    _instances[instance.id] = instance;
  }

  @override
  Future<void> update(PterodactylInstance instance) async {
    if (!_instances.containsKey(instance.id)) {
      throw const StorageException('missing');
    }
    _instances[instance.id] = instance;
  }

  @override
  Future<void> remove(String instanceId) async {
    _instances.remove(instanceId);
    if (_activeId == instanceId) _activeId = null;
  }

  @override
  Future<String?> getActiveInstanceId() async => _activeId;

  @override
  Future<void> setActiveInstanceId(String? instanceId) async => _activeId = instanceId;
}

class _FakeCredentialStorage implements CredentialStorage {
  final Map<String, InstanceCredentials> _store = {};

  @override
  Future<void> save(String instanceId, InstanceCredentials credentials) async {
    _store[instanceId] = credentials;
  }

  @override
  Future<InstanceCredentials?> read(String instanceId) async => _store[instanceId];

  @override
  Future<void> delete(String instanceId) async => _store.remove(instanceId);
}

ProviderContainer _buildContainer({
  required _FakeInstanceRepository repository,
  required _FakeCredentialStorage credentialStorage,
  PterodactylApiClientFactory? apiClientFactory,
}) {
  final container = ProviderContainer(
    retry: noAutomaticProviderRetry,
    overrides: [
      instanceRepositoryProvider.overrideWithValue(repository),
      credentialStorageProvider.overrideWithValue(credentialStorage),
      if (apiClientFactory != null) apiClientFactoryProvider.overrideWithValue(apiClientFactory),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('InstanceListController.build', () {
    test('loads instances and the active id from the repository', () async {
      final repository = _FakeInstanceRepository();
      await repository.add(_instanceA);
      await repository.setActiveInstanceId(_instanceA.id);

      final container = _buildContainer(repository: repository, credentialStorage: _FakeCredentialStorage());
      final state = await container.read(instanceListControllerProvider.future);

      expect(state.instances, [_instanceA]);
      expect(state.activeInstanceId, _instanceA.id);
    });

    test('starts with an empty list and no active instance when nothing is stored', () async {
      final container = _buildContainer(
        repository: _FakeInstanceRepository(),
        credentialStorage: _FakeCredentialStorage(),
      );
      final state = await container.read(instanceListControllerProvider.future);

      expect(state.instances, isEmpty);
      expect(state.activeInstanceId, isNull);
    });
  });

  group('InstanceListController.addInstance', () {
    test('stores the instance and its credentials, and activates the first instance added', () async {
      final credentialStorage = _FakeCredentialStorage();
      final container = _buildContainer(repository: _FakeInstanceRepository(), credentialStorage: credentialStorage);
      await container.read(instanceListControllerProvider.future);

      final notifier = container.read(instanceListControllerProvider.notifier);
      await notifier.addInstance(
        name: 'Home server',
        baseUrl: 'https://panel.example.com/',
        apiKey: 'ptlc_1234567890',
      );

      final state = container.read(instanceListControllerProvider).value!;
      expect(state.instances, hasLength(1));
      final added = state.instances.single;
      expect(added.name, 'Home server');
      expect(added.baseUrl, 'https://panel.example.com', reason: 'trailing slash must be normalized away');
      expect(state.activeInstanceId, added.id);

      final storedCredentials = await credentialStorage.read(added.id);
      expect(storedCredentials?.apiKey, 'ptlc_1234567890');
    });

    test('does not change the active instance when one is already set', () async {
      final container = _buildContainer(
        repository: _FakeInstanceRepository(),
        credentialStorage: _FakeCredentialStorage(),
      );
      await container.read(instanceListControllerProvider.future);
      final notifier = container.read(instanceListControllerProvider.notifier);

      await notifier.addInstance(name: 'First', baseUrl: 'https://a.example.com', apiKey: 'aaaaaaaaaa');
      final firstId = container.read(instanceListControllerProvider).value!.instances.single.id;

      await notifier.addInstance(name: 'Second', baseUrl: 'https://b.example.com', apiKey: 'bbbbbbbbbb');
      final state = container.read(instanceListControllerProvider).value!;

      expect(state.instances, hasLength(2));
      expect(state.activeInstanceId, firstId);
    });
  });

  group('InstanceListController.removeInstance', () {
    test('deletes the instance and its credentials, clearing active id if it was active', () async {
      final credentialStorage = _FakeCredentialStorage();
      final container = _buildContainer(repository: _FakeInstanceRepository(), credentialStorage: credentialStorage);
      await container.read(instanceListControllerProvider.future);
      final notifier = container.read(instanceListControllerProvider.notifier);

      await notifier.addInstance(name: 'Home', baseUrl: 'https://panel.example.com', apiKey: 'aaaaaaaaaa');
      final id = container.read(instanceListControllerProvider).value!.instances.single.id;

      await notifier.removeInstance(id);

      final state = container.read(instanceListControllerProvider).value!;
      expect(state.instances, isEmpty);
      expect(state.activeInstanceId, isNull);
      expect(await credentialStorage.read(id), isNull);
    });
  });

  group('InstanceListController.setActiveInstance', () {
    test('updates the active instance and persists the choice', () async {
      final repository = _FakeInstanceRepository();
      final container = _buildContainer(repository: repository, credentialStorage: _FakeCredentialStorage());
      await container.read(instanceListControllerProvider.future);
      final notifier = container.read(instanceListControllerProvider.notifier);

      await notifier.addInstance(name: 'First', baseUrl: 'https://a.example.com', apiKey: 'aaaaaaaaaa');
      await notifier.addInstance(name: 'Second', baseUrl: 'https://b.example.com', apiKey: 'bbbbbbbbbb');
      final secondId = container.read(instanceListControllerProvider).value!.instances[1].id;

      await notifier.setActiveInstance(secondId);

      expect(container.read(instanceListControllerProvider).value!.activeInstanceId, secondId);
      expect(await repository.getActiveInstanceId(), secondId);
    });

    test('is a no-op for an unknown instance id', () async {
      final container = _buildContainer(
        repository: _FakeInstanceRepository(),
        credentialStorage: _FakeCredentialStorage(),
      );
      await container.read(instanceListControllerProvider.future);
      final notifier = container.read(instanceListControllerProvider.notifier);

      await notifier.addInstance(name: 'First', baseUrl: 'https://a.example.com', apiKey: 'aaaaaaaaaa');
      final before = container.read(instanceListControllerProvider).value!;

      await notifier.setActiveInstance('does-not-exist');

      expect(container.read(instanceListControllerProvider).value!.activeInstanceId, before.activeInstanceId);
    });
  });

  // Regression coverage for the "Nie udało się połączyć" report: a release
  // APK missing `android.permission.INTERNET` in the merged manifest made
  // *every* request fail as a NetworkException, indistinguishable in the
  // UI from a genuinely unreachable panel. These exercise the real
  // request/response/exception-mapping contract `testConnection` promises
  // — a real local `HttpServer` standing in for the Panel (so parsing,
  // headers, and status-code mapping are all genuinely exercised, not
  // mocked away) for the success/401 cases, and the same
  // connect-to-nothing / connect-and-never-respond tricks already used by
  // `api_client_factory_test.dart` for the network/timeout cases — no
  // mocking library, no fake success.
  group('InstanceListController.testConnection', () {
    test('valid URL + valid API key -> null (successful connection test)', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      unawaited(server.forEach((request) {
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'data': []}))
          ..close();
      }));

      final container = _buildContainer(
        repository: _FakeInstanceRepository(),
        credentialStorage: _FakeCredentialStorage(),
      );
      final notifier = container.read(instanceListControllerProvider.notifier);

      final error = await notifier.testConnection(
        baseUrl: 'http://${server.address.address}:${server.port}',
        apiKey: 'ptlc_valid_key',
      );

      expect(error, isNull);
    });

    test('401 response -> UnauthorizedException (invalid credentials)', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      unawaited(server.forEach((request) {
        request.response
          ..statusCode = 401
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'errors': []}))
          ..close();
      }));

      final container = _buildContainer(
        repository: _FakeInstanceRepository(),
        credentialStorage: _FakeCredentialStorage(),
      );
      final notifier = container.read(instanceListControllerProvider.notifier);

      final error = await notifier.testConnection(
        baseUrl: 'http://${server.address.address}:${server.port}',
        apiKey: 'ptlc_wrong_key',
      );

      expect(error, isA<UnauthorizedException>());
      expect(error!.statusCode, 401);
    });

    test('an unresolvable host -> NetworkException (connection error)', () async {
      final container = _buildContainer(
        repository: _FakeInstanceRepository(),
        credentialStorage: _FakeCredentialStorage(),
        apiClientFactory: const PterodactylApiClientFactory(
          config: ApiClientConfig(connectTimeout: Duration(seconds: 5)),
        ),
      );
      final notifier = container.read(instanceListControllerProvider.notifier);

      // `.invalid` (RFC 2606) is reserved specifically to never resolve —
      // a real, fast DNS failure (`SocketException`), the same failure
      // mode a missing `INTERNET` permission or an unreachable panel
      // produces. Deliberately not "connect to a closed port": whether
      // that fails fast (connection refused) or hangs until timeout is
      // itself OS/sandbox-dependent, which made this assertion flaky.
      final error = await notifier.testConnection(
        baseUrl: 'http://this-panel-does-not-exist.invalid',
        apiKey: 'ptlc_key',
      );

      expect(error, isA<NetworkException>());
    });

    test('a host that never responds -> RequestTimeoutException', () async {
      final container = _buildContainer(
        repository: _FakeInstanceRepository(),
        credentialStorage: _FakeCredentialStorage(),
        apiClientFactory: const PterodactylApiClientFactory(
          config: ApiClientConfig(connectTimeout: Duration(milliseconds: 300)),
        ),
      );
      final notifier = container.read(instanceListControllerProvider.notifier);

      // TEST-NET-1 (RFC 5737, 192.0.2.0/24): reserved for documentation —
      // guaranteed to never route to a real host, so the connection
      // genuinely hangs until the configured timeout fires, deterministically.
      final error = await notifier.testConnection(baseUrl: 'http://192.0.2.1', apiKey: 'ptlc_key');

      expect(error, isA<RequestTimeoutException>());
    });
  });
}
