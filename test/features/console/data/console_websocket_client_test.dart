import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pterodactyl_mobile/features/console/data/console_websocket_client.dart';

import '../../../support/fake_console_transport.dart';

void main() {
  group('ConsoleWebSocketClient — decoding', () {
    test('decodes a valid frame into a ConsoleProtocolMessage', () async {
      final transport = FakeConsoleTransport();
      final client = ConsoleWebSocketClient(transport);
      addTearDown(client.dispose);

      final future = client.messages.first;
      transport.pushFrame('console output', ['hello world']);

      final message = await future;
      expect(message.event, 'console output');
      expect(message.joinedArgs, 'hello world');
    });

    test('drops a non-string frame instead of crashing', () async {
      final transport = FakeConsoleTransport();
      final client = ConsoleWebSocketClient(transport);
      addTearDown(client.dispose);

      final received = <dynamic>[];
      final sub = client.messages.listen(received.add);
      addTearDown(sub.cancel);

      transport.pushRaw(1234); // Wings only ever sends text frames
      transport.pushFrame('console output', ['still works']);
      await pumpEventQueue();

      expect(received, hasLength(1));
      expect(received.single.event, 'console output');
    });

    test('drops a frame that is not valid JSON instead of crashing', () async {
      final transport = FakeConsoleTransport();
      final client = ConsoleWebSocketClient(transport);
      addTearDown(client.dispose);

      final received = <dynamic>[];
      final sub = client.messages.listen(received.add);
      addTearDown(sub.cancel);

      transport.pushRaw('not json at all {{{');
      transport.pushFrame('console output', ['still works']);
      await pumpEventQueue();

      expect(received, hasLength(1));
    });

    test('drops a JSON frame that is not an object instead of crashing', () async {
      final transport = FakeConsoleTransport();
      final client = ConsoleWebSocketClient(transport);
      addTearDown(client.dispose);

      final received = <dynamic>[];
      final sub = client.messages.listen(received.add);
      addTearDown(sub.cancel);

      transport.pushRaw(jsonEncode([1, 2, 3]));
      transport.pushFrame('console output', ['still works']);
      await pumpEventQueue();

      expect(received, hasLength(1));
    });

    test('drops a well-formed JSON object missing a string "event" instead of crashing', () async {
      final transport = FakeConsoleTransport();
      final client = ConsoleWebSocketClient(transport);
      addTearDown(client.dispose);

      final received = <dynamic>[];
      final sub = client.messages.listen(received.add);
      addTearDown(sub.cancel);

      transport.pushRaw(jsonEncode({'not_event': 'value'}));
      transport.pushFrame('console output', ['still works']);
      await pumpEventQueue();

      expect(received, hasLength(1));
    });
  });

  group('ConsoleWebSocketClient — sending', () {
    test('send() encodes event and args as {"event":..., "args":[...]}', () async {
      final transport = FakeConsoleTransport();
      final client = ConsoleWebSocketClient(transport);
      addTearDown(client.dispose);

      await client.send('auth', ['token-value']);

      expect(transport.sent, hasLength(1));
      expect(jsonDecode(transport.sent.single), {
        'event': 'auth',
        'args': ['token-value'],
      });
    });

    test('send() with no args omits the "args" key entirely', () async {
      final transport = FakeConsoleTransport();
      final client = ConsoleWebSocketClient(transport);
      addTearDown(client.dispose);

      await client.send('send logs');

      expect(jsonDecode(transport.sent.single), {'event': 'send logs'});
    });
  });

  group('ConsoleWebSocketClient — lifecycle', () {
    test('done completes once the transport closes, and closeCode/closeReason are exposed', () async {
      final transport = FakeConsoleTransport();
      final client = ConsoleWebSocketClient(transport);
      addTearDown(client.dispose);

      expect(client.closeCode, isNull);

      await transport.simulateRemoteClose(4409, 'Server suspended');
      await client.done;

      expect(client.closeCode, 4409);
      expect(client.closeReason, 'Server suspended');
    });
  });
}
