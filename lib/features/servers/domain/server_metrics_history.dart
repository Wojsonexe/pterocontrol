import 'package:meta/meta.dart';

/// One real, observed resource reading for a server, timestamped — the
/// unit `ServerMetricsHistory` accumulates. Never synthesized: every
/// instance here corresponds to an actual `GET .../resources` response
/// `ServerRuntimeSyncController` received (see that class's `_sampleFor`).
///
/// [networkRxRateBytesPerSecond]/[networkTxRateBytesPerSecond] are
/// **derived**, not raw — Wings reports network bytes as a cumulative
/// counter since the container started, not a rate. A rate is computed
/// from the delta between this sample and the previous *real* one for the
/// same server, divided by the elapsed wall-clock time — still real data,
/// just expressed as "bytes/sec" instead of "bytes since boot", which is
/// the only form a sparkline/instantaneous throughput reading can use.
/// `null` for a server's first-ever sample (no previous point to diff
/// against yet) — shown as "moment temu" in the UI, never as `0 B/s`
/// (which would misleadingly claim the server observably had zero
/// throughput, rather than "not measured yet").
@immutable
class MetricSample {
  const MetricSample({
    required this.timestamp,
    required this.cpuPercent,
    required this.memoryBytes,
    this.networkRxRateBytesPerSecond,
    this.networkTxRateBytesPerSecond,
  });

  final DateTime timestamp;
  final double cpuPercent;
  final int memoryBytes;
  final double? networkRxRateBytesPerSecond;
  final double? networkTxRateBytesPerSecond;
}

/// A short, bounded rolling window of a server's real [MetricSample]s —
/// what `Sparkline`s on the Dashboard's resource-overview card and (later)
/// anywhere else that wants a trend, not just a current value, read from.
///
/// Bounded (see [ServerRuntimeSyncController]'s `_maxHistorySamples`) so
/// memory use stays flat for the lifetime of a session regardless of how
/// long the app has been polling — a sparkline only ever needs the last
/// few minutes, not a full history.
@immutable
class ServerMetricsHistory {
  const ServerMetricsHistory({this.samples = const []});

  static const empty = ServerMetricsHistory();

  final List<MetricSample> samples;

  MetricSample? get latest => samples.isEmpty ? null : samples.last;

  List<double> get cpuSeries => [for (final s in samples) s.cpuPercent];

  List<double> get memoryBytesSeries => [for (final s in samples) s.memoryBytes.toDouble()];

  /// Combined (rx+tx) throughput series, in bytes/sec — for a single
  /// "network activity" sparkline rather than two overlapping lines.
  /// Samples missing a rate (a server's very first reading) contribute
  /// `0` to keep the series' length aligned with the others, but do not
  /// themselves imply the server had no traffic — see [MetricSample].
  List<double> get networkThroughputSeries => [
        for (final s in samples) (s.networkRxRateBytesPerSecond ?? 0) + (s.networkTxRateBytesPerSecond ?? 0),
      ];

  ServerMetricsHistory appending(MetricSample sample, {required int maxLength}) {
    final next = [...samples, sample];
    final trimmed = next.length > maxLength ? next.sublist(next.length - maxLength) : next;
    return ServerMetricsHistory(samples: trimmed);
  }
}
