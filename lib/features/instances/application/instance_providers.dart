import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/shared_preferences_provider.dart';
import '../data/local_instance_repository.dart';
import '../domain/instance_repository.dart';

/// The app-wide [InstanceRepository].
///
/// Depends on [sharedPreferencesProvider], so it can only be read after
/// that provider has been overridden with a resolved `SharedPreferences`
/// instance (see `main.dart`).
final instanceRepositoryProvider = Provider<InstanceRepository>((ref) {
  final preferences = ref.watch(sharedPreferencesProvider);
  return LocalInstanceRepository(preferences);
});
