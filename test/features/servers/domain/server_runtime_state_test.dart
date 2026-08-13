import 'package:flutter_test/flutter_test.dart';
import 'package:pterodactyl_mobile/features/servers/domain/server_power_state.dart';
import 'package:pterodactyl_mobile/features/servers/domain/server_runtime_state.dart';

void main() {
  group('ServerRuntimeState', () {
    test('unknown has no observedAt', () {
      expect(ServerRuntimeState.unknown.powerState, ServerPowerState.unknown);
      expect(ServerRuntimeState.unknown.observedAt, isNull);
    });

    test('two instances with identical fields are equal', () {
      final observedAt = DateTime(2026, 1, 1, 12);
      final a = ServerRuntimeState(powerState: ServerPowerState.running, observedAt: observedAt);
      final b = ServerRuntimeState(powerState: ServerPowerState.running, observedAt: observedAt);

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('instances differing by powerState are not equal', () {
      final observedAt = DateTime(2026, 1, 1, 12);
      final running = ServerRuntimeState(powerState: ServerPowerState.running, observedAt: observedAt);
      final offline = ServerRuntimeState(powerState: ServerPowerState.offline, observedAt: observedAt);

      expect(running, isNot(equals(offline)));
    });

    test('instances differing by observedAt are not equal', () {
      const powerState = ServerPowerState.starting;
      final a = ServerRuntimeState(powerState: powerState, observedAt: DateTime(2026, 1, 1));
      final b = ServerRuntimeState(powerState: powerState, observedAt: DateTime(2026, 1, 2));

      expect(a, isNot(equals(b)));
    });

    test('hasResourceReading is false until a resource reading arrives', () {
      const withoutReading = ServerRuntimeState(powerState: ServerPowerState.running);
      expect(withoutReading.hasResourceReading, isFalse);

      const withReading = ServerRuntimeState(powerState: ServerPowerState.running, cpuAbsolutePercent: 12.5);
      expect(withReading.hasResourceReading, isTrue);
    });

    test('copyWith replaces only the given fields', () {
      const original = ServerRuntimeState(
        powerState: ServerPowerState.running,
        cpuAbsolutePercent: 10,
        memoryBytes: 100,
      );

      final updated = original.copyWith(cpuAbsolutePercent: 20);

      expect(updated.powerState, ServerPowerState.running);
      expect(updated.cpuAbsolutePercent, 20);
      expect(updated.memoryBytes, 100);
    });

    test('instances differing by a resource field are not equal', () {
      const a = ServerRuntimeState(powerState: ServerPowerState.running, memoryBytes: 100);
      const b = ServerRuntimeState(powerState: ServerPowerState.running, memoryBytes: 200);

      expect(a, isNot(equals(b)));
    });

    test('two instances with identical resource fields are equal', () {
      const a = ServerRuntimeState(
        powerState: ServerPowerState.running,
        cpuAbsolutePercent: 1.5,
        memoryBytes: 100,
        diskBytes: 200,
        networkRxBytes: 10,
        networkTxBytes: 20,
        uptimeMs: 5000,
      );
      const b = ServerRuntimeState(
        powerState: ServerPowerState.running,
        cpuAbsolutePercent: 1.5,
        memoryBytes: 100,
        diskBytes: 200,
        networkRxBytes: 10,
        networkTxBytes: 20,
        uptimeMs: 5000,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });
}
