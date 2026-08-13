import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pterodactyl_mobile/app/app_provider_policy.dart';
import 'package:pterodactyl_mobile/core/theme/app_theme.dart';
import 'package:pterodactyl_mobile/features/console/application/console_providers.dart';
import 'package:pterodactyl_mobile/features/console/data/console_protocol_events.dart';
import 'package:pterodactyl_mobile/features/console/domain/console_connection_state.dart';
import 'package:pterodactyl_mobile/features/console/domain/console_event.dart';
import 'package:pterodactyl_mobile/features/console/domain/console_repository.dart';
import 'package:pterodactyl_mobile/features/instances/application/instance_providers.dart';
import 'package:pterodactyl_mobile/features/instances/domain/instance_repository.dart';
import 'package:pterodactyl_mobile/features/instances/domain/pterodactyl_instance.dart';
import 'package:pterodactyl_mobile/features/servers/application/servers_providers.dart';
import 'package:pterodactyl_mobile/features/servers/domain/server.dart';
import 'package:pterodactyl_mobile/features/servers/domain/server_page.dart';
import 'package:pterodactyl_mobile/features/servers/domain/server_power_action.dart';
import 'package:pterodactyl_mobile/features/servers/domain/server_repository.dart';
import 'package:pterodactyl_mobile/features/servers/domain/server_runtime_state.dart';
import 'package:pterodactyl_mobile/features/servers/presentation/screens/server_detail_screen.dart';

const _instanceId = 'instance-a';
const _instance = PterodactylInstance(id: _instanceId, name: 'Home server', baseUrl: 'https://a.example.com');

Server _fivem({required ServerAdministrativeStatus status}) => Server(
      identifier: 'fivem',
      uuid: 'uuid-fivem',
      name: 'fivem',
      node: 'Node 1',
      status: status,
      isTransferring: false,
      limits: const ServerLimits(memoryMb: 4096, diskMb: 20480, cpuPercent: 200),
    );

class _FakeInstanceRepository implements InstanceRepository {
  final _instances = <String, PterodactylInstance>{_instanceId: _instance};

  @override
  Future<List<PterodactylInstance>> getAll() async => _instances.values.toList();

  @override
  Future<void> add(PterodactylInstance instance) async => _instances[instance.id] = instance;

  @override
  Future<void> update(PterodactylInstance instance) async => _instances[instance.id] = instance;

  @override
  Future<void> remove(String instanceId) async => _instances.remove(instanceId);

  @override
  Future<String?> getActiveInstanceId() async => _instanceId;

  @override
  Future<void> setActiveInstanceId(String? instanceId) async {}
}

/// A repository whose `getServer` returns whatever [current] points to at
/// call time — lets a test flip the "installing" -> "active" fixture
/// *after* the widget tree is already showing the stale one, the same way
/// a real reinstall completing would.
class _FakeServerRepository implements ServerRepository {
  _FakeServerRepository(this.current);

  Server current;
  int getServerCallCount = 0;

  @override
  Future<ServerPage> getServers({int page = 1}) async => ServerPage(servers: [current], page: 1, totalPages: 1);

  @override
  Future<void> sendPowerAction(String serverIdentifier, ServerPowerAction action) async {
    throw UnimplementedError('not exercised by this test');
  }

  @override
  Future<Server> getServer(String serverIdentifier) async {
    getServerCallCount++;
    return current;
  }

  @override
  Future<ServerRuntimeState> getResourceUsage(String serverIdentifier) async => ServerRuntimeState.unknown;
}

/// A [ConsoleRepository] whose [events] stream a test can push frames onto
/// directly — everything else is inert, matching `_NoopConsoleRepository`
/// in `servers_navigation_test.dart`.
class _ControllableConsoleRepository implements ConsoleRepository {
  final _eventsController = StreamController<List<ConsoleEvent>>.broadcast();

  @override
  Stream<ConsoleConnectionState> get connectionState => const Stream.empty();

  @override
  Stream<ServerRuntimeState> get runtimeState => const Stream.empty();

  @override
  Stream<List<ConsoleEvent>> get events => _eventsController.stream;

  void pushEvents(List<ConsoleEvent> events) => _eventsController.add(events);

  @override
  Future<void> connect() async {}

  @override
  Future<void> disconnect() async {}

  @override
  void sendCommand(String command) {}

  @override
  Future<void> dispose() async {
    await _eventsController.close();
  }
}

void main() {
  testWidgets(
    'an "install completed" WS event refreshes the server without leaving the screen',
    (tester) async {
      final serverRepository = _FakeServerRepository(_fivem(status: ServerAdministrativeStatus.installing));
      final consoleRepository = _ControllableConsoleRepository();
      addTearDown(consoleRepository.dispose);

      await tester.pumpWidget(
        ProviderScope(
          retry: noAutomaticProviderRetry,
          overrides: [
            instanceRepositoryProvider.overrideWithValue(_FakeInstanceRepository()),
            serverRepositoryProvider(_instanceId).overrideWithValue(serverRepository),
            consoleRepositoryProvider((instanceId: _instanceId, serverIdentifier: 'fivem'))
                .overrideWithValue(consoleRepository),
          ],
          child: MaterialApp(theme: AppTheme.light(), home: const ServerDetailScreen(serverId: 'fivem')),
        ),
      );
      // Not pumpAndSettle: the "installing" status badge shows an
      // indeterminate `CircularProgressIndicator`, whose animation never
      // settles — a couple of bounded pumps are enough to let the fake
      // repository's Futures and the 200ms status cross-fade resolve.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('Instalacja…'), findsOneWidget);
      expect(find.text('Aktywny'), findsNothing);

      // The install actually finishes on the backend — the next
      // `getServer` call would now report `active`.
      serverRepository.current = _fivem(status: ServerAdministrativeStatus.active);
      consoleRepository.pushEvents([
        ConsoleEvent(type: ConsoleEventType.unknown, message: ConsoleProtocolEvent.installCompleted, timestamp: DateTime.now()),
      ]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(
        serverRepository.getServerCallCount,
        greaterThan(0),
        reason: '"install completed" should trigger a targeted re-fetch of just this server',
      );
      expect(
        find.text('Aktywny'),
        findsWidgets,
        reason: 'the status chip(s) should flip without leaving the screen — header badge and Overview tab both show it',
      );
      expect(find.text('Instalacja…'), findsNothing);
    },
  );
}
