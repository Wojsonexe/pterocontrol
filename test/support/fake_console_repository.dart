import 'dart:async';

import 'package:pterodactyl_mobile/features/console/domain/console_connection_state.dart';
import 'package:pterodactyl_mobile/features/console/domain/console_event.dart';
import 'package:pterodactyl_mobile/features/console/domain/console_repository.dart';
import 'package:pterodactyl_mobile/features/servers/domain/server_runtime_state.dart';

/// A [ConsoleRepository] whose three streams are driven manually by a
/// test, and whose lifecycle methods just record how many times they were
/// called — for testing `ConsoleController`/`ConsoleView` without a real
/// connection underneath.
class FakeConsoleRepository implements ConsoleRepository {
  final _connectionStateController = StreamController<ConsoleConnectionState>.broadcast();
  final _runtimeStateController = StreamController<ServerRuntimeState>.broadcast();
  final _eventsController = StreamController<List<ConsoleEvent>>.broadcast();

  int connectCallCount = 0;
  int disconnectCallCount = 0;
  final sentCommands = <String>[];

  @override
  Stream<ConsoleConnectionState> get connectionState => _connectionStateController.stream;

  @override
  Stream<ServerRuntimeState> get runtimeState => _runtimeStateController.stream;

  @override
  Stream<List<ConsoleEvent>> get events => _eventsController.stream;

  @override
  Future<void> connect() async => connectCallCount++;

  @override
  Future<void> disconnect() async => disconnectCallCount++;

  @override
  void sendCommand(String command) => sentCommands.add(command);

  @override
  Future<void> dispose() async {
    await _connectionStateController.close();
    await _runtimeStateController.close();
    await _eventsController.close();
  }

  void emitConnectionState(ConsoleConnectionState state) => _connectionStateController.add(state);

  void emitRuntimeState(ServerRuntimeState state) => _runtimeStateController.add(state);

  void emitEvents(List<ConsoleEvent> events) => _eventsController.add(events);

  bool get hasAnySubscriber =>
      _connectionStateController.hasListener || _runtimeStateController.hasListener || _eventsController.hasListener;
}
