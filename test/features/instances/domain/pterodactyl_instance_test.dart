import 'package:flutter_test/flutter_test.dart';
import 'package:pterodactyl_mobile/features/instances/domain/pterodactyl_instance.dart';

void main() {
  group('PterodactylInstance', () {
    const instance = PterodactylInstance(
      id: 'instance-1',
      name: 'Home server',
      baseUrl: 'https://panel.example.com',
    );

    test('defaults connectionStatus and authState when not provided', () {
      expect(instance.connectionStatus, InstanceConnectionStatus.unknown);
      expect(instance.authState, InstanceAuthState.unauthenticated);
      expect(instance.panelVersion, isNull);
    });

    test('copyWith overrides only the given fields', () {
      final updated = instance.copyWith(connectionStatus: InstanceConnectionStatus.online);

      expect(updated.connectionStatus, InstanceConnectionStatus.online);
      expect(updated.id, instance.id);
      expect(updated.name, instance.name);
      expect(updated.baseUrl, instance.baseUrl);
      expect(updated.authState, instance.authState);
    });

    test('copyWith never changes the id', () {
      final updated = instance.copyWith(name: 'Renamed');

      expect(updated.id, instance.id);
      expect(updated.name, 'Renamed');
    });

    test('two instances with identical fields are equal', () {
      const other = PterodactylInstance(
        id: 'instance-1',
        name: 'Home server',
        baseUrl: 'https://panel.example.com',
      );

      expect(instance, equals(other));
      expect(instance.hashCode, equals(other.hashCode));
    });

    test('instances differing by a single field are not equal', () {
      final renamed = instance.copyWith(name: 'Different name');

      expect(instance, isNot(equals(renamed)));
    });
  });
}
