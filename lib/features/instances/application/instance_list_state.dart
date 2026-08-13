import 'package:meta/meta.dart';

import '../domain/pterodactyl_instance.dart';

/// State exposed by [InstanceListController]: every configured instance,
/// plus which one (if any) is currently active.
@immutable
class InstanceListState {
  const InstanceListState({required this.instances, this.activeInstanceId});

  final List<PterodactylInstance> instances;
  final String? activeInstanceId;

  PterodactylInstance? get activeInstance {
    final id = activeInstanceId;
    return id == null ? null : findById(id);
  }

  PterodactylInstance? findById(String instanceId) {
    for (final instance in instances) {
      if (instance.id == instanceId) return instance;
    }
    return null;
  }
}
