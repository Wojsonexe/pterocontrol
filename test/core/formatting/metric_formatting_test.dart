import 'package:flutter_test/flutter_test.dart';
import 'package:pterodactyl_mobile/core/formatting/metric_formatting.dart';

void main() {
  group('formatFileSize', () {
    test('bytes stay as bytes below 1 KB', () {
      expect(formatFileSize(0), '0 B');
      expect(formatFileSize(512), '512 B');
      expect(formatFileSize(1023), '1023 B');
    });

    test('scales to KB, MB, GB at the right thresholds', () {
      expect(formatFileSize(1024), '1.0 KB');
      expect(formatFileSize(1536), '1.5 KB');
      expect(formatFileSize(1024 * 1024), '1.0 MB');
      expect(formatFileSize(1024 * 1024 * 1024), '1.0 GB');
    });

    test('a small config file never reads as "0 MB"', () {
      // The exact regression this exists for — formatBytesAsMb(200) would
      // print "0 MB", which reads as broken for a real, non-empty file.
      expect(formatFileSize(200), '200 B');
    });
  });
}
