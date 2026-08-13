import 'package:flutter_test/flutter_test.dart';
import 'package:pterodactyl_mobile/features/servers/domain/server_metrics_history.dart';

void main() {
  group('ServerMetricsHistory', () {
    test('empty has no samples', () {
      expect(ServerMetricsHistory.empty.samples, isEmpty);
      expect(ServerMetricsHistory.empty.latest, isNull);
    });

    test('appending adds a sample and exposes it as latest', () {
      final sample = MetricSample(timestamp: DateTime(2026), cpuPercent: 10, memoryBytes: 100);
      final history = ServerMetricsHistory.empty.appending(sample, maxLength: 5);

      expect(history.samples, [sample]);
      expect(history.latest, sample);
    });

    test('drops the oldest samples once maxLength is exceeded', () {
      var history = ServerMetricsHistory.empty;
      for (var i = 0; i < 5; i++) {
        history = history.appending(
          MetricSample(timestamp: DateTime(2026, 1, 1, i), cpuPercent: i.toDouble(), memoryBytes: i),
          maxLength: 3,
        );
      }

      expect(history.samples, hasLength(3));
      expect(history.cpuSeries, [2.0, 3.0, 4.0], reason: 'oldest two samples (0, 1) should have been dropped');
    });

    test('cpuSeries/memoryBytesSeries expose one value per sample in order', () {
      final history = ServerMetricsHistory(samples: [
        MetricSample(timestamp: DateTime(2026), cpuPercent: 10, memoryBytes: 1000),
        MetricSample(timestamp: DateTime(2026), cpuPercent: 15, memoryBytes: 1200),
      ]);

      expect(history.cpuSeries, [10.0, 15.0]);
      expect(history.memoryBytesSeries, [1000.0, 1200.0]);
    });

    test('networkThroughputSeries sums rx+tx per sample, treating an unmeasured rate as 0', () {
      final history = ServerMetricsHistory(samples: [
        MetricSample(timestamp: DateTime(2026), cpuPercent: 0, memoryBytes: 0),
        MetricSample(
          timestamp: DateTime(2026),
          cpuPercent: 0,
          memoryBytes: 0,
          networkRxRateBytesPerSecond: 100,
          networkTxRateBytesPerSecond: 50,
        ),
      ]);

      expect(
        history.networkThroughputSeries,
        [0, 150],
        reason: 'the first sample has no previous point to diff against — it contributes 0, not a crash',
      );
    });
  });
}
