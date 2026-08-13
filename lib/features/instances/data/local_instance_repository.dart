import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/error/app_exception.dart';
import '../domain/instance_repository.dart';
import '../domain/pterodactyl_instance.dart';
import 'instance_local_dto.dart';

/// [InstanceRepository] backed by [SharedPreferences].
///
/// Only instance *metadata* is stored here (see [InstanceLocalDto]) — never
/// API keys or other secrets. [SharedPreferences] is unencrypted, which is
/// fine for "which panels has the user added" but would not be for
/// credentials; that distinction is exactly why credentials go through a
/// separate `CredentialStorage`.
class LocalInstanceRepository implements InstanceRepository {
  LocalInstanceRepository(this._preferences);

  final SharedPreferences _preferences;

  static const _instancesKey = 'instances.list.v1';
  static const _activeInstanceKey = 'instances.active_id.v1';

  @override
  Future<List<PterodactylInstance>> getAll() async {
    final raw = _preferences.getStringList(_instancesKey) ?? const <String>[];
    try {
      return raw
          .map((entry) => InstanceLocalDto.fromJson(jsonDecode(entry) as Map<String, dynamic>).toInstance())
          .toList(growable: false);
    } catch (error) {
      throw StorageException('Nie udało się odczytać zapisanych instancji.', cause: error);
    }
  }

  @override
  Future<void> add(PterodactylInstance instance) async {
    final current = await getAll();
    if (current.any((existing) => existing.id == instance.id)) {
      throw StorageException('Instancja o tym identyfikatorze już istnieje.');
    }
    await _writeAll([...current, instance]);
  }

  @override
  Future<void> update(PterodactylInstance instance) async {
    final current = await getAll();
    final index = current.indexWhere((existing) => existing.id == instance.id);
    if (index == -1) {
      throw StorageException('Nie znaleziono instancji do zaktualizowania.');
    }
    final updated = List<PterodactylInstance>.of(current);
    updated[index] = instance;
    await _writeAll(updated);
  }

  @override
  Future<void> remove(String instanceId) async {
    final current = await getAll();
    await _writeAll(current.where((instance) => instance.id != instanceId).toList());

    if (await getActiveInstanceId() == instanceId) {
      await setActiveInstanceId(null);
    }
  }

  @override
  Future<String?> getActiveInstanceId() async {
    return _preferences.getString(_activeInstanceKey);
  }

  @override
  Future<void> setActiveInstanceId(String? instanceId) async {
    if (instanceId == null) {
      await _preferences.remove(_activeInstanceKey);
    } else {
      await _preferences.setString(_activeInstanceKey, instanceId);
    }
  }

  Future<void> _writeAll(List<PterodactylInstance> instances) async {
    final encoded = instances
        .map((instance) => jsonEncode(InstanceLocalDto.fromInstance(instance).toJson()))
        .toList(growable: false);
    final ok = await _preferences.setStringList(_instancesKey, encoded);
    if (!ok) {
      throw const StorageException('Nie udało się zapisać listy instancji na urządzeniu.');
    }
  }
}
