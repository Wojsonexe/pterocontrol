import 'package:flutter/foundation.dart';

/// Lightweight, debug-only timing trace for diagnosing dashboard load
/// performance — see README, "Synchronizacja stanu serwerów" /
/// dashboard-performance notes. `[tag] message` lines, printed through
/// Flutter's `debugPrint` (same convention `PterodactylApiClientFactory`'s
/// `LogInterceptor` already uses) so they show up in `flutter logs`/
/// `adb logcat` without needing a separate tool.
///
/// `kDebugMode`-gated: compiles to nothing in a release build, and is not
/// used for any functional decision anywhere — purely a human-readable
/// trace of *when* each stage of a load actually happened, so a claim
/// like "the resource endpoint is slow" is measured, not guessed.
void perfLog(String tag, String message) {
  if (!kDebugMode) return;
  debugPrint('[$tag] $message');
}
