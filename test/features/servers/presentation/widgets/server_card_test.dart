import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pterodactyl_mobile/core/presentation/widgets/skeleton_box.dart';
import 'package:pterodactyl_mobile/core/theme/app_theme.dart';
import 'package:pterodactyl_mobile/features/servers/domain/server.dart';
import 'package:pterodactyl_mobile/features/servers/domain/server_power_state.dart';
import 'package:pterodactyl_mobile/features/servers/domain/server_runtime_state.dart';
import 'package:pterodactyl_mobile/features/servers/presentation/widgets/server_card.dart';

const _server = Server(
  identifier: 'srv-1',
  uuid: 'uuid-srv-1',
  name: 'Survival SMP',
  node: 'Node 1',
  status: ServerAdministrativeStatus.active,
  isTransferring: false,
  limits: ServerLimits(memoryMb: 2048, diskMb: 10240, cpuPercent: 100),
);

Widget _wrap(Widget child) => MaterialApp(theme: AppTheme.light(), home: Scaffold(body: child));

void main() {
  group('ServerCard', () {
    testWidgets('shows a skeleton placeholder while the first fetch is in flight', (tester) async {
      await tester.pumpWidget(_wrap(ServerCard(server: _server, isRefreshing: true, onTap: () {})));
      await tester.pump();

      expect(find.byType(SkeletonBox), findsOneWidget);
      expect(find.text('—'), findsNothing);
      expect(find.textContaining('oczekiwanie'), findsNothing, reason: 'the old, indefinitely-stuck wording is gone');
    });

    testWidgets('shows a quiet dash when there is no data and nothing is in flight', (tester) async {
      await tester.pumpWidget(_wrap(ServerCard(server: _server, onTap: () {})));
      await tester.pump();

      expect(find.text('—'), findsOneWidget);
    });

    testWidgets('shows a failure caption when there is no data and the first attempt failed', (tester) async {
      await tester.pumpWidget(_wrap(ServerCard(server: _server, hasRecentFailure: true, onTap: () {})));
      await tester.pump();

      expect(find.text('Nie udało się odświeżyć'), findsOneWidget);
      expect(find.text('—'), findsNothing);
    });

    testWidgets('keeps showing the last known values while a refresh is in progress', (tester) async {
      await tester.pumpWidget(
        _wrap(
          ServerCard(
            server: _server,
            runtimeState: const ServerRuntimeState(powerState: ServerPowerState.running, cpuAbsolutePercent: 27),
            isRefreshing: true,
            onTap: () {},
          ),
        ),
      );
      await tester.pump();

      expect(find.text('27%'), findsOneWidget, reason: 'a refresh in flight must never blank out the last reading');
      expect(find.text('Aktualizowanie…'), findsOneWidget);
    });

    testWidgets('shows a failure caption alongside existing values without hiding them', (tester) async {
      await tester.pumpWidget(
        _wrap(
          ServerCard(
            server: _server,
            runtimeState: const ServerRuntimeState(powerState: ServerPowerState.running, cpuAbsolutePercent: 27),
            hasRecentFailure: true,
            onTap: () {},
          ),
        ),
      );
      await tester.pump();

      expect(find.text('27%'), findsOneWidget);
      expect(find.text('Nie udało się odświeżyć'), findsOneWidget);
    });

    testWidgets('shows a relative staleness timestamp once data has settled', (tester) async {
      final observedAt = DateTime.now().subtract(const Duration(minutes: 5));
      await tester.pumpWidget(
        _wrap(
          ServerCard(
            server: _server,
            runtimeState: ServerRuntimeState(
              powerState: ServerPowerState.running,
              observedAt: observedAt,
              cpuAbsolutePercent: 27,
            ),
            onTap: () {},
          ),
        ),
      );
      await tester.pump();

      expect(find.text('27%'), findsOneWidget);
      expect(find.text('5 min temu'), findsOneWidget);
      expect(find.text('Aktualizowanie…'), findsNothing);
      expect(find.text('Nie udało się odświeżyć'), findsNothing);
    });
  });
}
