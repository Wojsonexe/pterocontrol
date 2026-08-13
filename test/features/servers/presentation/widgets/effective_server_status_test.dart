import 'package:flutter_test/flutter_test.dart';
import 'package:pterodactyl_mobile/core/theme/app_status_tokens.dart';
import 'package:pterodactyl_mobile/features/servers/domain/server.dart';
import 'package:pterodactyl_mobile/features/servers/domain/server_power_state.dart';
import 'package:pterodactyl_mobile/features/servers/presentation/widgets/effective_server_status.dart';

void main() {
  group('effectiveServerStatus', () {
    test('suspended always wins, regardless of a stale/live power reading', () {
      final visual = effectiveServerStatus(
        administrativeStatus: ServerAdministrativeStatus.suspended,
        powerState: ServerPowerState.running,
      );
      expect(visual.label, 'Zawieszony');
      expect(visual.tone, AppStatusTone.danger);
    });

    test('installFailed and reinstallFailed both read as a single danger "Błąd" state', () {
      for (final status in [ServerAdministrativeStatus.installFailed, ServerAdministrativeStatus.reinstallFailed]) {
        final visual = effectiveServerStatus(administrativeStatus: status, powerState: null);
        expect(visual.label, 'Błąd');
        expect(visual.tone, AppStatusTone.danger);
      }
    });

    test('installing is an animated pending state, independent of power state', () {
      final visual = effectiveServerStatus(
        administrativeStatus: ServerAdministrativeStatus.installing,
        powerState: ServerPowerState.offline,
      );
      expect(visual.label, 'Instalacja');
      expect(visual.tone, AppStatusTone.pending);
      expect(visual.isAnimated, isTrue);
    });

    test('restoringBackup is an animated pending state', () {
      final visual = effectiveServerStatus(
        administrativeStatus: ServerAdministrativeStatus.restoringBackup,
        powerState: null,
      );
      expect(visual.label, 'Przywracanie');
      expect(visual.isAnimated, isTrue);
    });

    test('unknown administrative status reads as neutral', () {
      final visual = effectiveServerStatus(
        administrativeStatus: ServerAdministrativeStatus.unknown,
        powerState: ServerPowerState.running,
      );
      expect(visual.tone, AppStatusTone.neutral);
    });

    test('active + no power reading yet reads as success "Aktywny", not unknown/neutral', () {
      final visual = effectiveServerStatus(administrativeStatus: ServerAdministrativeStatus.active, powerState: null);
      expect(visual.label, 'Aktywny');
      expect(visual.tone, AppStatusTone.success);
    });

    test('active + running reads as success "Aktywny"', () {
      final visual = effectiveServerStatus(
        administrativeStatus: ServerAdministrativeStatus.active,
        powerState: ServerPowerState.running,
      );
      expect(visual.label, 'Aktywny');
      expect(visual.tone, AppStatusTone.success);
    });

    test('active + unknown power state falls back to success "Aktywny", same as no reading', () {
      final visual = effectiveServerStatus(
        administrativeStatus: ServerAdministrativeStatus.active,
        powerState: ServerPowerState.unknown,
      );
      expect(visual.label, 'Aktywny');
    });

    test('active + starting is an animated pending "Uruchamianie"', () {
      final visual = effectiveServerStatus(
        administrativeStatus: ServerAdministrativeStatus.active,
        powerState: ServerPowerState.starting,
      );
      expect(visual.label, 'Uruchamianie');
      expect(visual.tone, AppStatusTone.pending);
      expect(visual.isAnimated, isTrue);
    });

    test('active + stopping is an animated pending "Zatrzymywanie"', () {
      final visual = effectiveServerStatus(
        administrativeStatus: ServerAdministrativeStatus.active,
        powerState: ServerPowerState.stopping,
      );
      expect(visual.label, 'Zatrzymywanie');
      expect(visual.tone, AppStatusTone.pending);
      expect(visual.isAnimated, isTrue);
    });

    test('active + offline reads as a neutral "Zatrzymany", not danger', () {
      final visual = effectiveServerStatus(
        administrativeStatus: ServerAdministrativeStatus.active,
        powerState: ServerPowerState.offline,
      );
      expect(visual.label, 'Zatrzymany');
      expect(visual.tone, AppStatusTone.neutral);
    });
  });
}
