import 'package:flutter_test/flutter_test.dart';
import 'package:pterodactyl_mobile/features/console/data/console_protocol_message.dart';

void main() {
  group('ConsoleProtocolMessage.fromJson', () {
    test('parses an event with a single-element args array', () {
      final message = ConsoleProtocolMessage.fromJson({
        'event': 'console output',
        'args': ['Server started'],
      });

      expect(message.event, 'console output');
      expect(message.args, ['Server started']);
      expect(message.joinedArgs, 'Server started');
    });

    test('joins a multi-element args array back into one string', () {
      // Wings splits some payloads across multiple array elements — the
      // client must reassemble them with `Join`, not just take args[0].
      final message = ConsoleProtocolMessage.fromJson({
        'event': 'console output',
        'args': ['line one', 'line two'],
      });

      expect(message.joinedArgs, 'line oneline two');
    });

    test('defaults args to an empty list when the field is absent', () {
      final message = ConsoleProtocolMessage.fromJson({'event': 'auth success'});

      expect(message.args, isEmpty);
      expect(message.joinedArgs, '');
    });

    test('coerces non-string args elements to strings instead of throwing', () {
      final message = ConsoleProtocolMessage.fromJson({
        'event': 'stats',
        'args': [42, true],
      });

      expect(message.args, ['42', 'true']);
    });

    test('throws FormatException when "event" is missing', () {
      expect(() => ConsoleProtocolMessage.fromJson({'args': []}), throwsFormatException);
    });

    test('throws FormatException when "event" is not a string', () {
      expect(() => ConsoleProtocolMessage.fromJson({'event': 42}), throwsFormatException);
    });
  });

  group('ConsoleProtocolMessage.toJson', () {
    test('omits "args" entirely when empty', () {
      const message = ConsoleProtocolMessage(event: 'send logs');

      expect(message.toJson(), {'event': 'send logs'});
    });

    test('includes "args" when non-empty', () {
      const message = ConsoleProtocolMessage(event: 'auth', args: ['token-value']);

      expect(message.toJson(), {
        'event': 'auth',
        'args': ['token-value'],
      });
    });
  });
}
