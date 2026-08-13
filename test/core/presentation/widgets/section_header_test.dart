import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pterodactyl_mobile/core/presentation/widgets/section_header.dart';

void main() {
  group('SectionHeader', () {
    testWidgets('renders the title', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SectionHeader('Informacje'))),
      );

      expect(find.text('Informacje'), findsOneWidget);
    });

    testWidgets('renders trailing content when provided', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SectionHeader('Konsola', trailing: const Icon(Icons.refresh)),
          ),
        ),
      );

      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });

    testWidgets('renders without a trailing widget when none is given', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SectionHeader('Informacje'))),
      );

      expect(find.byType(Icon), findsNothing);
    });
  });
}
