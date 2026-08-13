import 'package:flutter_test/flutter_test.dart';
import 'package:pterodactyl_mobile/features/console/domain/console_event.dart';

void main() {
  group('ConsoleEvent', () {
    test('two instances with identical fields are equal', () {
      final timestamp = DateTime(2026, 1, 1, 12);
      final a = ConsoleEvent(type: ConsoleEventType.output, message: 'Server started', timestamp: timestamp);
      final b = ConsoleEvent(type: ConsoleEventType.output, message: 'Server started', timestamp: timestamp);

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('instances differing by type are not equal', () {
      final timestamp = DateTime(2026, 1, 1, 12);
      final output = ConsoleEvent(type: ConsoleEventType.output, message: 'same text', timestamp: timestamp);
      final daemonMessage = ConsoleEvent(
        type: ConsoleEventType.daemonMessage,
        message: 'same text',
        timestamp: timestamp,
      );

      expect(output, isNot(equals(daemonMessage)));
    });

    test('instances differing by message are not equal', () {
      final timestamp = DateTime(2026, 1, 1, 12);
      final a = ConsoleEvent(type: ConsoleEventType.output, message: 'a', timestamp: timestamp);
      final b = ConsoleEvent(type: ConsoleEventType.output, message: 'b', timestamp: timestamp);

      expect(a, isNot(equals(b)));
    });
  });
}
