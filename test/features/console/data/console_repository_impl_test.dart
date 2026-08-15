import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pterodactyl_mobile/core/network/pterodactyl_api_client.dart';
import 'package:pterodactyl_mobile/features/console/data/console_api.dart';
import 'package:pterodactyl_mobile/features/console/data/console_repository_impl.dart';
import 'package:pterodactyl_mobile/features/console/domain/console_connection_state.dart';
import 'package:pterodactyl_mobile/features/console/domain/console_event.dart';
import 'package:pterodactyl_mobile/features/servers/domain/server_power_state.dart';
import 'package:pterodactyl_mobile/features/servers/domain/server_runtime_state.dart';

import '../../../support/fake_console_transport.dart';
import '../../../support/fake_http_client_adapter.dart';

/// Builds a [ConsoleApi] whose HTTP responses come from [handler] — no
/// real network involved. [callCount] is incremented on every request, so
/// tests can assert how many times the token endpoint was actually hit
/// (e.g. once per (re)connect attempt, once more per token refresh).
({ConsoleApi api, List<RequestOptions> requests}) _buildApi(
  FutureOr<ResponseBody> Function(RequestOptions options) handler,
) {
  final requests = <RequestOptions>[];
  final adapter = FakeHttpClientAdapter((options) {
    requests.add(options);
    return handler(options);
  });
  final dio = Dio(BaseOptions(baseUrl: 'https://panel.example.com'))..httpClientAdapter = adapter;
  return (api: ConsoleApi(PterodactylApiClient(dio: dio)), requests: requests);
}

ResponseBody _tokenResponse({String token = 'token-1', String socket = 'wss://node.example.com/api/servers/u/ws'}) {
  return jsonResponseBody({
    'data': {'token': token, 'socket': socket},
  });
}

ConsoleRepositoryImpl _buildRepository({
  required ConsoleApi api,
  required FakeConsoleTransportConnector connector,
  Duration Function(int attempt)? backoffForAttempt,
  int maxBufferSize = 500,
}) {
  return ConsoleRepositoryImpl(
    api: api,
    serverIdentifier: 'd3aac109',
    transportConnector: connector.connect,
    backoffForAttempt: backoffForAttempt ?? (_) => Duration.zero,
    maxBufferSize: maxBufferSize,
  );
}

void main() {
  group('ConsoleRepositoryImpl — connection state transitions', () {
    test('goes disconnected -> connecting -> authenticating -> connected on a successful connect', () async {
      final (:api, :requests) = _buildApi((_) async => _tokenResponse());
      final connector = FakeConsoleTransportConnector();
      final transport = FakeConsoleTransport();
      connector.enqueueTransport(transport);
      final repository = _buildRepository(api: api, connector: connector);
      addTearDown(repository.dispose);

      final states = <ConsoleConnectionState>[];
      final sub = repository.connectionState.listen(states.add);
      addTearDown(sub.cancel);

      await repository.connect();
      await pumpEventQueue();
      expect(
        states,
        [ConsoleConnectionState.connecting, ConsoleConnectionState.authenticating],
        reason: 'the transport opens (connecting), then the auth frame is sent (authenticating) — '
            'both happen before Wings ever replies',
      );

      transport.pushFrame('auth success');
      await pumpEventQueue();

      expect(
        states,
        [ConsoleConnectionState.connecting, ConsoleConnectionState.authenticating, ConsoleConnectionState.connected],
      );
      expect(requests, hasLength(1));
    });
  });

  group('ConsoleRepositoryImpl — authentication', () {
    test('sends {"event":"auth","args":[token]} as the first frame after the transport opens', () async {
      final (:api, :requests) = _buildApi((_) async => _tokenResponse(token: 'super-secret-jwt'));
      final connector = FakeConsoleTransportConnector();
      final transport = FakeConsoleTransport();
      connector.enqueueTransport(transport);
      final repository = _buildRepository(api: api, connector: connector);
      addTearDown(repository.dispose);

      await repository.connect();
      await pumpEventQueue();

      expect(transport.sent, hasLength(1));
      expect(transport.sent.single, contains('"event":"auth"'));
      expect(transport.sent.single, contains('super-secret-jwt'));
    });

    test('connects to the exact socket URL returned by the token endpoint', () async {
      final (:api, :requests) = _buildApi(
        (_) async => _tokenResponse(socket: 'wss://node7.example.com/api/servers/abc/ws'),
      );
      final connector = FakeConsoleTransportConnector();
      connector.enqueueTransport(FakeConsoleTransport());
      final repository = _buildRepository(api: api, connector: connector);
      addTearDown(repository.dispose);

      await repository.connect();
      await pumpEventQueue();

      expect(connector.requestedUrls.single, Uri.parse('wss://node7.example.com/api/servers/abc/ws'));
    });

    test('sends "send logs" only after auth success, to request backlog', () async {
      final (:api, :requests) = _buildApi((_) async => _tokenResponse());
      final connector = FakeConsoleTransportConnector();
      final transport = FakeConsoleTransport();
      connector.enqueueTransport(transport);
      final repository = _buildRepository(api: api, connector: connector);
      addTearDown(repository.dispose);

      await repository.connect();
      await pumpEventQueue();
      expect(transport.sent, hasLength(1), reason: 'only "auth" so far, no backlog request yet');

      transport.pushFrame('auth success');
      await pumpEventQueue();

      expect(transport.sent, hasLength(2));
      expect(transport.sent.last, contains('"event":"send logs"'));
    });
  });

  group('ConsoleRepositoryImpl — ConsoleEvent mapping', () {
    Future<ConsoleRepositoryImpl> connected(FakeConsoleTransport transport, List<List<ConsoleEvent>> events) async {
      final (:api, :requests) = _buildApi((_) async => _tokenResponse());
      final connector = FakeConsoleTransportConnector()..enqueueTransport(transport);
      final repository = _buildRepository(api: api, connector: connector);
      repository.events.listen(events.add);
      await repository.connect();
      await pumpEventQueue();
      transport.pushFrame('auth success');
      await pumpEventQueue();
      return repository;
    }

    test('maps "console output" and "install output" to ConsoleEventType.output', () async {
      final transport = FakeConsoleTransport();
      final events = <List<ConsoleEvent>>[];
      final repository = await connected(transport, events);
      addTearDown(repository.dispose);

      transport.pushFrame('console output', ['Server started']);
      transport.pushFrame('install output', ['Running installer...']);
      await pumpEventQueue();

      final last = events.last;
      expect(last.map((e) => e.type), [ConsoleEventType.output, ConsoleEventType.output]);
      expect(last.map((e) => e.message), ['Server started', 'Running installer...']);
    });

    test('maps "daemon message" and "daemon error" to their own event types', () async {
      final transport = FakeConsoleTransport();
      final events = <List<ConsoleEvent>>[];
      final repository = await connected(transport, events);
      addTearDown(repository.dispose);

      transport.pushFrame('daemon message', ['Backup starting']);
      transport.pushFrame('daemon error', ['Disk quota exceeded']);
      await pumpEventQueue();

      final last = events.last;
      expect(last[0].type, ConsoleEventType.daemonMessage);
      expect(last[0].message, 'Backup starting');
      expect(last[1].type, ConsoleEventType.daemonError);
      expect(last[1].message, 'Disk quota exceeded');
    });

    test('"status" updates runtimeState and is not added to the console event buffer', () async {
      final transport = FakeConsoleTransport();
      final events = <List<ConsoleEvent>>[];
      final repository = await connected(transport, events);
      addTearDown(repository.dispose);

      final runtimeStates = <ServerPowerState>[];
      repository.runtimeState.listen((s) => runtimeStates.add(s.powerState));

      transport.pushFrame('status', ['running']);
      await pumpEventQueue();

      expect(runtimeStates, [ServerPowerState.running]);
      expect(events.last, isEmpty, reason: '"status" must not appear as console text');
    });

    for (final raw in ['offline', 'starting', 'running', 'stopping']) {
      test('maps status "$raw" to the matching ServerPowerState', () async {
        final transport = FakeConsoleTransport();
        final events = <List<ConsoleEvent>>[];
        final repository = await connected(transport, events);
        addTearDown(repository.dispose);

        final runtimeStates = <ServerPowerState>[];
        repository.runtimeState.listen((s) => runtimeStates.add(s.powerState));

        transport.pushFrame('status', [raw]);
        await pumpEventQueue();

        expect(runtimeStates.single.name, raw);
      });
    }
  });

  group('ConsoleRepositoryImpl — unknown protocol messages', () {
    test('unrecognized events are kept as ConsoleEventType.unknown instead of dropped or crashing', () async {
      final (:api, :requests) = _buildApi((_) async => _tokenResponse());
      final transport = FakeConsoleTransport();
      final connector = FakeConsoleTransportConnector()..enqueueTransport(transport);
      final repository = _buildRepository(api: api, connector: connector);
      addTearDown(repository.dispose);
      final events = <List<ConsoleEvent>>[];
      repository.events.listen(events.add);

      await repository.connect();
      await pumpEventQueue();
      transport.pushFrame('auth success');
      await pumpEventQueue();

      transport.pushFrame('backup completed:11111111-1111-1111-1111-111111111111');
      transport.pushFrame('install started');
      transport.pushFrame('deleted');
      await pumpEventQueue();

      final unknown = events.last.where((e) => e.type == ConsoleEventType.unknown).toList();
      expect(unknown, hasLength(3));
      expect(unknown.map((e) => e.message), [
        'backup completed:11111111-1111-1111-1111-111111111111',
        'install started',
        'deleted',
      ]);
    });
  });

  group('ConsoleRepositoryImpl — "stats" telemetry', () {
    test('"stats" is a known event and produces no ConsoleEvent at all (not even "unknown")', () async {
      final (:api, :requests) = _buildApi((_) async => _tokenResponse());
      final transport = FakeConsoleTransport();
      final connector = FakeConsoleTransportConnector()..enqueueTransport(transport);
      final repository = _buildRepository(api: api, connector: connector);
      addTearDown(repository.dispose);
      final events = <List<ConsoleEvent>>[];
      repository.events.listen(events.add);

      await repository.connect();
      await pumpEventQueue();
      transport.pushFrame('auth success');
      await pumpEventQueue();
      final eventsAfterAuth = events.length;

      // Wings broadcasts this repeatedly (every few seconds) for a running
      // server — it must never leak into the console buffer/UI as text.
      transport.pushFrame('stats', ['{"memory_bytes":1024,"cpu_absolute":12.5}']);
      transport.pushFrame('stats', ['{"memory_bytes":2048,"cpu_absolute":13.1}']);
      transport.pushFrame('stats', ['{"memory_bytes":4096,"cpu_absolute":9.9}']);
      await pumpEventQueue();

      expect(
        events.length,
        eventsAfterAuth,
        reason: 'the events stream must not emit at all in response to "stats" frames',
      );
      final lastBuffer = events.isEmpty ? const <ConsoleEvent>[] : events.last;
      expect(lastBuffer, isEmpty, reason: '"stats" must never be added to the console buffer, not even as unknown');
    });

    test('"stats" does not interfere with real console output arriving around it', () async {
      final (:api, :requests) = _buildApi((_) async => _tokenResponse());
      final transport = FakeConsoleTransport();
      final connector = FakeConsoleTransportConnector()..enqueueTransport(transport);
      final repository = _buildRepository(api: api, connector: connector);
      addTearDown(repository.dispose);
      final events = <List<ConsoleEvent>>[];
      repository.events.listen(events.add);

      await repository.connect();
      await pumpEventQueue();
      transport.pushFrame('auth success');
      await pumpEventQueue();

      transport.pushFrame('console output', ['Server started']);
      transport.pushFrame('stats', ['{"memory_bytes":1024}']);
      transport.pushFrame('console output', ['Loading world...']);
      await pumpEventQueue();

      expect(events.last.map((e) => e.message), ['Server started', 'Loading world...']);
      expect(events.last, everyElement(predicate<ConsoleEvent>((e) => e.type == ConsoleEventType.output)));
    });

    test('parses a full stats frame into a ServerRuntimeState on runtimeState', () async {
      final (:api, :requests) = _buildApi((_) async => _tokenResponse());
      final transport = FakeConsoleTransport();
      final connector = FakeConsoleTransportConnector()..enqueueTransport(transport);
      final repository = _buildRepository(api: api, connector: connector);
      addTearDown(repository.dispose);
      final runtimeStates = <ServerRuntimeState>[];
      repository.runtimeState.listen(runtimeStates.add);

      await repository.connect();
      await pumpEventQueue();
      transport.pushFrame('auth success');
      await pumpEventQueue();
      final afterAuthCount = runtimeStates.length; // "status" already added one

      transport.pushFrame('stats', [
        '{"state":"running","memory_bytes":536870912,"memory_limit_bytes":1073741824,'
            '"cpu_absolute":17.25,"disk_bytes":204800,"network":{"rx_bytes":111,"tx_bytes":222},'
            '"uptime":90000}',
      ]);
      await pumpEventQueue();

      expect(runtimeStates.length, afterAuthCount + 1);
      final stats = runtimeStates.last;
      expect(stats.powerState, ServerPowerState.running);
      expect(stats.cpuAbsolutePercent, 17.25);
      expect(stats.memoryBytes, 536870912);
      expect(stats.diskBytes, 204800);
      expect(stats.networkRxBytes, 111);
      expect(stats.networkTxBytes, 222);
      expect(stats.uptimeMs, 90000);
      expect(stats.hasResourceReading, isTrue);
    });

    test('a malformed stats frame is ignored instead of crashing the session', () async {
      final (:api, :requests) = _buildApi((_) async => _tokenResponse());
      final transport = FakeConsoleTransport();
      final connector = FakeConsoleTransportConnector()..enqueueTransport(transport);
      final repository = _buildRepository(api: api, connector: connector);
      addTearDown(repository.dispose);
      final runtimeStates = <ServerRuntimeState>[];
      repository.runtimeState.listen(runtimeStates.add);

      await repository.connect();
      await pumpEventQueue();
      transport.pushFrame('auth success');
      await pumpEventQueue();
      final afterAuthCount = runtimeStates.length;

      transport.pushFrame('stats', ['not-json']);
      await pumpEventQueue();

      expect(runtimeStates.length, afterAuthCount, reason: 'a malformed frame must not push a bogus reading');

      transport.pushFrame('console output', ['still alive']);
      await pumpEventQueue();
      // No crash — the connection keeps working after the malformed frame.
    });
  });

  group('ConsoleRepositoryImpl — console buffer limit', () {
    test('the events list never exceeds maxBufferSize, dropping the oldest lines first', () async {
      final (:api, :requests) = _buildApi((_) async => _tokenResponse());
      final transport = FakeConsoleTransport();
      final connector = FakeConsoleTransportConnector()..enqueueTransport(transport);
      final repository = _buildRepository(api: api, connector: connector, maxBufferSize: 3);
      addTearDown(repository.dispose);
      final events = <List<ConsoleEvent>>[];
      repository.events.listen(events.add);

      await repository.connect();
      await pumpEventQueue();
      transport.pushFrame('auth success');
      await pumpEventQueue();

      for (var i = 1; i <= 5; i++) {
        transport.pushFrame('console output', ['line $i']);
      }
      await pumpEventQueue();

      final last = events.last;
      expect(last, hasLength(3));
      expect(last.map((e) => e.message), ['line 3', 'line 4', 'line 5']);
    });
  });

  group('ConsoleRepositoryImpl — reconnect', () {
    test('on an unexpected close, reconnects with a freshly requested token and transport', () async {
      final (:api, :requests) = _buildApi((_) async => _tokenResponse());
      final firstTransport = FakeConsoleTransport();
      final secondTransport = FakeConsoleTransport();
      final connector = FakeConsoleTransportConnector()
        ..enqueueTransport(firstTransport)
        ..enqueueTransport(secondTransport);
      final repository = _buildRepository(api: api, connector: connector);
      addTearDown(repository.dispose);
      final states = <ConsoleConnectionState>[];
      repository.connectionState.listen(states.add);

      await repository.connect();
      await pumpEventQueue();
      firstTransport.pushFrame('auth success');
      await pumpEventQueue();
      expect(states.last, ConsoleConnectionState.connected);

      await firstTransport.simulateRemoteClose(1006, 'abnormal closure');
      await pumpEventQueue();
      expect(states, contains(ConsoleConnectionState.reconnecting));

      secondTransport.pushFrame('auth success');
      await pumpEventQueue();

      expect(states.last, ConsoleConnectionState.connected);
      expect(requests, hasLength(2), reason: 'a fresh token must be fetched for the reconnect attempt');
      expect(connector.requestedUrls, hasLength(2));
    });

    test('clears the console buffer on a genuine reconnect so old output is not duplicated', () async {
      final (:api, :requests) = _buildApi((_) async => _tokenResponse());
      final firstTransport = FakeConsoleTransport();
      final secondTransport = FakeConsoleTransport();
      final connector = FakeConsoleTransportConnector()
        ..enqueueTransport(firstTransport)
        ..enqueueTransport(secondTransport);
      final repository = _buildRepository(api: api, connector: connector);
      addTearDown(repository.dispose);
      final events = <List<ConsoleEvent>>[];
      repository.events.listen(events.add);

      await repository.connect();
      await pumpEventQueue();
      firstTransport.pushFrame('auth success');
      await pumpEventQueue();
      firstTransport.pushFrame('console output', ['before reconnect']);
      await pumpEventQueue();
      expect(events.last.map((e) => e.message), ['before reconnect']);

      await firstTransport.simulateRemoteClose(1006, 'abnormal closure');
      await pumpEventQueue();
      secondTransport.pushFrame('auth success');
      await pumpEventQueue();

      expect(events.last, isEmpty, reason: 'the buffer must be cleared on a fresh reconnect');

      secondTransport.pushFrame('console output', ['after reconnect']);
      await pumpEventQueue();
      expect(events.last.map((e) => e.message), ['after reconnect']);
    });

    test('does not reconnect after a 4409 (suspended) close code', () async {
      final (:api, :requests) = _buildApi((_) async => _tokenResponse());
      final transport = FakeConsoleTransport();
      final connector = FakeConsoleTransportConnector()..enqueueTransport(transport);
      final repository = _buildRepository(api: api, connector: connector);
      addTearDown(repository.dispose);
      final states = <ConsoleConnectionState>[];
      repository.connectionState.listen(states.add);

      await repository.connect();
      await pumpEventQueue();
      transport.pushFrame('auth success');
      await pumpEventQueue();

      await transport.simulateRemoteClose(4409, 'Server suspended');
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(states.last, ConsoleConnectionState.error);
      expect(requests, hasLength(1), reason: 'a suspended server must not trigger a reconnect attempt');
    });

    test('exponential backoff schedule is bounded and increasing', () {
      expect(defaultConsoleReconnectBackoff(0), const Duration(seconds: 1));
      expect(defaultConsoleReconnectBackoff(1), const Duration(seconds: 2));
      expect(defaultConsoleReconnectBackoff(2), const Duration(seconds: 4));
      expect(defaultConsoleReconnectBackoff(3), const Duration(seconds: 8));
      expect(defaultConsoleReconnectBackoff(4), const Duration(seconds: 16));
      expect(defaultConsoleReconnectBackoff(5), const Duration(seconds: 30), reason: 'capped, not 32s');
      expect(defaultConsoleReconnectBackoff(20), const Duration(seconds: 30), reason: 'stays capped for any later attempt');
    });

    test('jittered backoff stays within [base/2, base] and is actually random', () {
      // A fixed seed makes the *sequence* deterministic while still
      // exercising real randomization — this is not "assert the mock
      // returned what the mock returns", it is checking the real jitter
      // formula's output range and that it does not degenerate to a
      // constant.
      final random = Random(42);
      final samples = List.generate(50, (_) => jitteredConsoleReconnectBackoff(3, random: random));

      for (final sample in samples) {
        expect(sample.inMilliseconds, greaterThanOrEqualTo(4000), reason: 'never less than base/2 for attempt 3 (8s base)');
        expect(sample.inMilliseconds, lessThanOrEqualTo(8000), reason: 'never more than the base itself');
      }
      expect(samples.toSet().length, greaterThan(1), reason: 'jitter must actually vary, not collapse to one value');
    });

    test('jittered backoff never exceeds the 30s cap for a high attempt number', () {
      final random = Random(7);
      for (var i = 0; i < 20; i++) {
        final sample = jitteredConsoleReconnectBackoff(20, random: random);
        expect(sample.inMilliseconds, inInclusiveRange(15000, 30000));
      }
    });

    test('a failed token fetch schedules a reconnect using the injected backoff, not a tight loop', () async {
      var callCount = 0;
      final (:api, :requests) = _buildApi((_) {
        callCount++;
        return jsonResponseBody({'errors': []}, statusCode: 500);
      });
      final connector = FakeConsoleTransportConnector();
      final delays = <int>[];
      final repository = _buildRepository(
        api: api,
        connector: connector,
        backoffForAttempt: (attempt) {
          delays.add(attempt);
          return const Duration(milliseconds: 10);
        },
      );
      addTearDown(repository.dispose);

      await repository.connect();
      await Future<void>.delayed(const Duration(milliseconds: 45));

      expect(callCount, greaterThan(1), reason: 'must have retried at least once');
      expect(delays.length, greaterThanOrEqualTo(2), reason: 'must have scheduled more than one reconnect');
      expect(delays, equals(List.generate(delays.length, (i) => i)), reason: 'attempt counter must strictly increase, not repeat 0 forever');
    });
  });

  group('ConsoleRepositoryImpl — intentional disconnect', () {
    test('disconnect() prevents any further reconnect attempt', () async {
      final (:api, :requests) = _buildApi((_) async => _tokenResponse());
      final transport = FakeConsoleTransport();
      final connector = FakeConsoleTransportConnector()..enqueueTransport(transport);
      final repository = _buildRepository(api: api, connector: connector);
      addTearDown(repository.dispose);

      await repository.connect();
      await pumpEventQueue();
      transport.pushFrame('auth success');
      await pumpEventQueue();

      await repository.disconnect();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(requests, hasLength(1), reason: 'no reconnect attempt must follow an intentional disconnect');
    });

    test('disconnect() emits ConsoleConnectionState.disconnected', () async {
      final (:api, :requests) = _buildApi((_) async => _tokenResponse());
      final transport = FakeConsoleTransport();
      final connector = FakeConsoleTransportConnector()..enqueueTransport(transport);
      final repository = _buildRepository(api: api, connector: connector);
      addTearDown(repository.dispose);
      final states = <ConsoleConnectionState>[];
      repository.connectionState.listen(states.add);

      await repository.connect();
      await pumpEventQueue();
      transport.pushFrame('auth success');
      await pumpEventQueue();

      await repository.disconnect();
      await pumpEventQueue();

      expect(states.last, ConsoleConnectionState.disconnected);
    });
  });

  group('ConsoleRepositoryImpl — disposal', () {
    test('dispose() cancels a pending reconnect timer instead of letting it fire', () async {
      var callCount = 0;
      final (:api, :requests) = _buildApi((_) {
        callCount++;
        return jsonResponseBody({'errors': []}, statusCode: 500);
      });
      final connector = FakeConsoleTransportConnector();
      final repository = _buildRepository(
        api: api,
        connector: connector,
        backoffForAttempt: (_) => const Duration(milliseconds: 30),
      );

      await repository.connect();
      await pumpEventQueue(); // let the first (failing) attempt run and schedule a reconnect
      expect(callCount, 1);

      await repository.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(callCount, 1, reason: 'the scheduled reconnect must never fire after dispose()');
    });

    test('dispose() is safe to call when connect() was never called', () async {
      final (:api, :requests) = _buildApi((_) async => _tokenResponse());
      final connector = FakeConsoleTransportConnector();
      final repository = _buildRepository(api: api, connector: connector);

      await expectLater(repository.dispose(), completes);
      expect(requests, isEmpty);
    });

    test('connect() after dispose() is a no-op', () async {
      final (:api, :requests) = _buildApi((_) async => _tokenResponse());
      final connector = FakeConsoleTransportConnector();
      final repository = _buildRepository(api: api, connector: connector);

      await repository.dispose();
      await repository.connect();
      await pumpEventQueue();

      expect(requests, isEmpty);
    });
  });

  group('ConsoleRepositoryImpl — jwt error handling', () {
    test('a refreshable jwt error triggers a token refresh and re-auth on the same socket', () async {
      final (:api, :requests) = _buildApi((_) async => _tokenResponse(token: 'refreshed-token'));
      final transport = FakeConsoleTransport();
      final connector = FakeConsoleTransportConnector()..enqueueTransport(transport);
      final repository = _buildRepository(api: api, connector: connector);
      addTearDown(repository.dispose);

      await repository.connect();
      await pumpEventQueue();
      transport.pushFrame('auth success');
      await pumpEventQueue();
      final requestsBefore = requests.length;

      transport.pushFrame('jwt error', ['jwt: exp claim is invalid']);
      await pumpEventQueue();

      expect(requests.length, requestsBefore + 1, reason: 'must fetch a fresh token');
      expect(connector.requestedUrls, hasLength(1), reason: 'must reuse the existing socket, not reconnect');
      expect(transport.sent.last, contains('refreshed-token'));
    });

    test('a non-refreshable jwt error goes to the error state and stops automatic reconnects', () async {
      final (:api, :requests) = _buildApi((_) async => _tokenResponse());
      final transport = FakeConsoleTransport();
      final connector = FakeConsoleTransportConnector()..enqueueTransport(transport);
      final repository = _buildRepository(api: api, connector: connector);
      addTearDown(repository.dispose);
      final states = <ConsoleConnectionState>[];
      repository.connectionState.listen(states.add);

      await repository.connect();
      await pumpEventQueue();
      transport.pushFrame('auth success');
      await pumpEventQueue();

      transport.pushFrame('jwt error', ['jwt: missing connect permission']);
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(states.last, ConsoleConnectionState.error);
      expect(requests, hasLength(1), reason: 'a fatal jwt error must not trigger a reconnect attempt');
    });
  });

  group('ConsoleRepositoryImpl — token expiry', () {
    test('"token expiring" refreshes the token on the same socket without clearing the buffer', () async {
      final (:api, :requests) = _buildApi((_) async => _tokenResponse(token: 'refreshed-token'));
      final transport = FakeConsoleTransport();
      final connector = FakeConsoleTransportConnector()..enqueueTransport(transport);
      final repository = _buildRepository(api: api, connector: connector);
      addTearDown(repository.dispose);
      final events = <List<ConsoleEvent>>[];
      repository.events.listen(events.add);

      await repository.connect();
      await pumpEventQueue();
      transport.pushFrame('auth success');
      await pumpEventQueue();
      transport.pushFrame('console output', ['keep me']);
      await pumpEventQueue();
      final sentBefore = transport.sent.length;

      transport.pushFrame('token expiring');
      await pumpEventQueue();

      expect(events.last.map((e) => e.message), ['keep me'], reason: 'a same-socket refresh must not clear output');
      expect(transport.sent.length, sentBefore + 1, reason: 'exactly one new auth frame, no new "send logs"');
      expect(transport.sent.last, contains('"event":"auth"'));
      expect(transport.sent.last, contains('refreshed-token'));
    });
  });

  group('ConsoleRepositoryImpl — sendCommand', () {
    test('sendCommand is a no-op before authentication', () async {
      final (:api, :requests) = _buildApi((_) async => _tokenResponse());
      final transport = FakeConsoleTransport();
      final connector = FakeConsoleTransportConnector()..enqueueTransport(transport);
      final repository = _buildRepository(api: api, connector: connector);
      addTearDown(repository.dispose);

      await repository.connect();
      await pumpEventQueue();
      repository.sendCommand('say hello');
      await pumpEventQueue();

      expect(transport.sent, hasLength(1), reason: 'only the auth frame — the command must be dropped');
    });

    test('sendCommand sends {"event":"send command","args":[command]} once authenticated', () async {
      final (:api, :requests) = _buildApi((_) async => _tokenResponse());
      final transport = FakeConsoleTransport();
      final connector = FakeConsoleTransportConnector()..enqueueTransport(transport);
      final repository = _buildRepository(api: api, connector: connector);
      addTearDown(repository.dispose);

      await repository.connect();
      await pumpEventQueue();
      transport.pushFrame('auth success');
      await pumpEventQueue();

      repository.sendCommand('say hello');
      await pumpEventQueue();

      expect(transport.sent.last, contains('"event":"send command"'));
      expect(transport.sent.last, contains('say hello'));
    });
  });
}
