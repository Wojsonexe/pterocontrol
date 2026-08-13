import 'pterodactyl_instance.dart';

/// Persists the list of Pterodactyl instances the user has configured on
/// this device, and tracks which one is currently active.
///
/// Implementations must only store instance *metadata* (id, name, URL,
/// ...) — never [InstanceCredentials]; those go through
/// `CredentialStorage`. Keeping the two separate means the (currently
/// plaintext-friendly) instance list and the (must be encrypted)
/// credentials can use different storage backends without either one
/// knowing about the other.
abstract interface class InstanceRepository {
  Future<List<PterodactylInstance>> getAll();

  /// Adds [instance]. Throws a `StorageException` if an instance with the
  /// same id already exists.
  Future<void> add(PterodactylInstance instance);

  /// Replaces the stored instance with the same id as [instance]. Throws a
  /// `StorageException` if no such instance exists.
  Future<void> update(PterodactylInstance instance);

  Future<void> remove(String instanceId);

  Future<String?> getActiveInstanceId();

  Future<void> setActiveInstanceId(String? instanceId);
}
