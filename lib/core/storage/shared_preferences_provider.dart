import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The resolved [SharedPreferences] instance.
///
/// [SharedPreferences.getInstance] is asynchronous, but most of the app
/// needs synchronous access to storage-backed providers. Rather than wiring
/// every consumer through a [FutureProvider], `main()` resolves the
/// instance once before `runApp` and overrides this provider with the
/// value — the standard Riverpod pattern for bootstrap-time dependencies.
///
/// Reading this provider before that override is applied is a programming
/// error and throws intentionally.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'sharedPreferencesProvider must be overridden with a resolved '
    'SharedPreferences instance in main() before the app is built.',
  );
});
