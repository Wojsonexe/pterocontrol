/// Formats a byte count (as reported by Wings — `memory_bytes`,
/// `disk_bytes`, ...) as whole megabytes, matching how the rest of the app
/// already displays configured limits (`Server.limits`, in MB).
String formatBytesAsMb(int bytes) => '${(bytes / (1024 * 1024)).round()} MB';

/// Formats a container uptime in milliseconds (Wings' `uptime`) as a short
/// human-readable duration — the coarsest unit that is still non-zero,
/// plus one unit of precision below it (matching how most panels show
/// uptime: "2d 5h", not "2 days, 5 hours, 12 minutes, 3 seconds").
String formatUptime(int uptimeMs) {
  final duration = Duration(milliseconds: uptimeMs);
  final days = duration.inDays;
  final hours = duration.inHours.remainder(24);
  final minutes = duration.inMinutes.remainder(60);

  if (days > 0) return '${days}d ${hours}h';
  if (hours > 0) return '${hours}h ${minutes}m';
  return '${minutes}m';
}

/// Formats a network throughput rate (bytes/sec, derived from real
/// consecutive samples — see `MetricSample`) as a short human-readable
/// rate. `null` means "not measured yet" (a server's first-ever reading,
/// with nothing to diff against) and is rendered as an em dash, never as
/// a fabricated `0 B/s`.
String formatRate(double? bytesPerSecond) {
  if (bytesPerSecond == null) return '—';
  if (bytesPerSecond < 1024) return '${bytesPerSecond.round()} B/s';
  final kbPerSecond = bytesPerSecond / 1024;
  if (kbPerSecond < 1024) return '${kbPerSecond.toStringAsFixed(kbPerSecond < 10 ? 1 : 0)} KB/s';
  return '${(kbPerSecond / 1024).toStringAsFixed(1)} MB/s';
}

/// Formats [timestamp] relative to now — "aktualizacja: przed chwilą",
/// "12 s temu" — for a sync-freshness label (`ServerRuntimeSyncState`'s
/// most recent `observedAt`). Coarse on purpose: a user checking "is this
/// stale" needs "just now" vs. "a while ago", not a running stopwatch.
String formatRelativeTime(DateTime timestamp) {
  final elapsed = DateTime.now().difference(timestamp);
  if (elapsed.inSeconds < 5) return 'przed chwilą';
  if (elapsed.inSeconds < 60) return '${elapsed.inSeconds} s temu';
  if (elapsed.inMinutes < 60) return '${elapsed.inMinutes} min temu';
  if (elapsed.inHours < 24) return '${elapsed.inHours} godz. temu';
  return '${elapsed.inDays} dni temu';
}
