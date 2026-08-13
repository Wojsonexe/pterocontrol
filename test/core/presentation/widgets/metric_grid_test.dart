import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pterodactyl_mobile/core/presentation/widgets/metric_grid.dart';
import 'package:pterodactyl_mobile/core/theme/app_theme.dart';

void main() {
  group('MetricGrid', () {
    testWidgets('renders every item\'s label and value', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: MetricGrid(
              items: [
                MetricItem(icon: Icons.dns_outlined, label: 'Node', value: 'wojtek-server'),
                MetricItem(icon: Icons.memory_outlined, label: 'Pamięć RAM', value: '4096 MB'),
                MetricItem(icon: Icons.storage_outlined, label: 'Dysk', value: '10240 MB'),
                MetricItem(icon: Icons.speed_outlined, label: 'CPU', value: 'Bez limitu'),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Node'), findsOneWidget);
      expect(find.text('wojtek-server'), findsOneWidget);
      expect(find.text('Pamięć RAM'), findsOneWidget);
      expect(find.text('4096 MB'), findsOneWidget);
      expect(find.text('Dysk'), findsOneWidget);
      expect(find.text('10240 MB'), findsOneWidget);
      expect(find.text('CPU'), findsOneWidget);
      expect(find.text('Bez limitu'), findsOneWidget);
    });

    testWidgets('handles an odd number of items without throwing', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: MetricGrid(
              items: [
                MetricItem(icon: Icons.dns_outlined, label: 'Node', value: 'wojtek-server'),
                MetricItem(icon: Icons.memory_outlined, label: 'Pamięć RAM', value: '4096 MB'),
                MetricItem(icon: Icons.storage_outlined, label: 'Dysk', value: '10240 MB'),
              ],
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Dysk'), findsOneWidget);
    });

    testWidgets('handles an empty list without throwing', (tester) async {
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light(), home: const Scaffold(body: MetricGrid(items: []))),
      );

      expect(tester.takeException(), isNull);
    });
  });
}
