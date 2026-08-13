import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pterodactyl_mobile/core/presentation/widgets/sparkline.dart';

void main() {
  group('Sparkline', () {
    testWidgets('renders without throwing for an empty series', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Sparkline(values: [], color: Colors.blue))),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders without throwing for a single sample', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Sparkline(values: [42], color: Colors.blue))),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders without throwing when every value is identical (zero range)', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Sparkline(values: [5, 5, 5, 5], color: Colors.blue))),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders without throwing for a realistic trending series', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Sparkline(values: [10, 15, 12, 40, 38, 22, 8], color: Colors.blue)),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders without throwing for negative-capable/zero values', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Sparkline(values: [0, 0, 0.001, 0], color: Colors.blue))),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
