import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pterodactyl_mobile/app/app_provider_policy.dart';
import 'package:pterodactyl_mobile/app/lifecycle/app_lifecycle_controller.dart';
import 'package:pterodactyl_mobile/features/console/application/console_controller.dart';
import 'package:pterodactyl_mobile/features/console/application/console_providers.dart';
import 'package:pterodactyl_mobile/features/console/domain/console_connection_state.dart';
import 'package:pterodactyl_mobile/features/console/domain/console_event.dart';
import 'package:pterodactyl_mobile/features/servers/domain/server_power_state.dart';
import 'package:pterodactyl_mobile/features/servers/domain/server_runtime_state.dart';

import '../../../support/fake_console_repository.dart';

const _target = (instanceId: 'instance-a', serverIdentifier: 'srv-1');

ProviderContainer _buildContainer(FakeConsoleRepository repository) {
  final container = ProviderContainer(
    retry: noAutomaticProviderRetry,
    overrides: [consoleRepositoryProvider(_target).overrideWithValue(repository)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ConsoleController.build', () {
    test('connects immediately and starts in the initial state', () async {
      final repository = FakeConsoleRepository();
      final container = _buildContainer(repository);
      container.listen(consoleControllerProvider(_target), (_, _) {});

      final state = await container.read(consoleControllerProvider(_target).future);

      expect(repository.connectCallCount, 1);
      expect(state.connectionState, ConsoleConnectionState.disconnected);
      expect(state.runtimeState, ServerRuntimeState.unknown);
      expect(state.events, isEmpty);
    });

    test('a connectionState emission right after build() completes is captured, proving the subscription is already active', () async {
      final repository = FakeConsoleRepository();
      final container = _buildContainer(repository);
      final sub = container.listen(consoleControllerProvider(_target), (_, _) {});
      addTearDown(sub.close);
      await container.read(consoleControllerProvider(_target).future);

      // If ConsoleController subscribed *after* connect() instead of
      // before, this emission (representing the very first transition a
      // real repository could send the instant connect() is called)
      // would be silently missed.
      repository.emitConnectionState(ConsoleConnectionState.connecting);
      await pumpEventQueue();

      expect(
        container.read(consoleControllerProvider(_target)).value?.connectionState,
        ConsoleConnectionState.connecting,
      );
    });
  });

  group('ConsoleController — stream propagation', () {
    test('connectionState/runtimeState/events updates are merged into ConsoleState independently', () async {
      final repository = FakeConsoleRepository();
      final container = _buildContainer(repository);
      final sub = container.listen(consoleControllerProvider(_target), (_, _) {});
      addTearDown(sub.close);
      await container.read(consoleControllerProvider(_target).future);

      repository.emitConnectionState(ConsoleConnectionState.connected);
      await pumpEventQueue();
      var state = container.read(consoleControllerProvider(_target)).value!;
      expect(state.connectionState, ConsoleConnectionState.connected);
      expect(state.events, isEmpty);

      final events = [ConsoleEvent(type: ConsoleEventType.output, message: 'hi', timestamp: DateTime.now())];
      repository.emitEvents(events);
      await pumpEventQueue();
      state = container.read(consoleControllerProvider(_target)).value!;
      expect(state.events, events);
      expect(state.connectionState, ConsoleConnectionState.connected, reason: 'unrelated field must be untouched');

      repository.emitRuntimeState(const ServerRuntimeState(powerState: ServerPowerState.running));
      await pumpEventQueue();
      state = container.read(consoleControllerProvider(_target)).value!;
      expect(state.runtimeState.powerState, ServerPowerState.running);
      expect(state.events, events, reason: 'unrelated field must still be untouched');
    });
  });

  group('ConsoleController — delegation', () {
    test('sendCommand/reconnect/disconnect delegate to the repository', () async {
      final repository = FakeConsoleRepository();
      final container = _buildContainer(repository);
      final sub = container.listen(consoleControllerProvider(_target), (_, _) {});
      addTearDown(sub.close);
      await container.read(consoleControllerProvider(_target).future);
      final notifier = container.read(consoleControllerProvider(_target).notifier);

      notifier.sendCommand('say hi');
      expect(repository.sentCommands, ['say hi']);

      await notifier.reconnect();
      expect(repository.connectCallCount, 2, reason: 'once from build(), once from reconnect()');

      await notifier.disconnect();
      expect(repository.disconnectCallCount, 1);
    });
  });

  group('ConsoleController — app lifecycle', () {
    test('disconnects when the app is backgrounded and reconnects on foreground', () async {
      final repository = FakeConsoleRepository();
      final container = _buildContainer(repository);
      final sub = container.listen(consoleControllerProvider(_target), (_, _) {});
      addTearDown(sub.close);
      await container.read(consoleControllerProvider(_target).future);
      expect(repository.connectCallCount, 1, reason: 'the initial connect() from build()');

      container.read(appLifecycleControllerProvider.notifier).state = AppLifecycleState.paused;
      await pumpEventQueue();
      expect(repository.disconnectCallCount, 1);

      container.read(appLifecycleControllerProvider.notifier).state = AppLifecycleState.resumed;
      await pumpEventQueue();
      expect(repository.connectCallCount, 2, reason: 'reconnects immediately on returning to the foreground');
    });

    test('does not disconnect for a merely-inactive transition (e.g. a system dialog)', () async {
      final repository = FakeConsoleRepository();
      final container = _buildContainer(repository);
      final sub = container.listen(consoleControllerProvider(_target), (_, _) {});
      addTearDown(sub.close);
      await container.read(consoleControllerProvider(_target).future);

      container.read(appLifecycleControllerProvider.notifier).state = AppLifecycleState.inactive;
      await pumpEventQueue();

      expect(repository.disconnectCallCount, 0);
      expect(repository.connectCallCount, 1);
    });
  });

  group('ConsoleController — disposal', () {
    test('cancels its repository stream subscriptions when disposed', () async {
      final repository = FakeConsoleRepository();
      final container = ProviderContainer(
        retry: noAutomaticProviderRetry,
        overrides: [consoleRepositoryProvider(_target).overrideWithValue(repository)],
      );
      final sub = container.listen(consoleControllerProvider(_target), (_, _) {});
      await container.read(consoleControllerProvider(_target).future);

      expect(repository.hasAnySubscriber, isTrue);

      sub.close();
      container.dispose();
      await pumpEventQueue();

      expect(repository.hasAnySubscriber, isFalse);
    });
  });
}
