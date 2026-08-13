import 'package:flutter_test/flutter_test.dart';
import 'package:pterodactyl_mobile/core/theme/app_radius.dart';

void main() {
  group('AppRadius', () {
    test('scale matches the accepted design-system values', () {
      expect(AppRadius.xs, 8);
      expect(AppRadius.sm, 12);
      expect(AppRadius.md, 16);
      expect(AppRadius.lg, 24);
    });

    test('full is unbounded, so BorderRadius.circular(full) always yields a fully rounded shape', () {
      expect(AppRadius.full, double.infinity);
    });
  });
}
