import '../domain/pterodactyl_instance.dart';

/// JSON representation of [PterodactylInstance] used for local persistence.
///
/// Kept separate from the domain entity so the domain layer stays ignorant
/// of *how* (or whether) instances are persisted, and so the on-disk format
/// can change independently of [PterodactylInstance]. Runtime-only fields
/// ([PterodactylInstance.connectionStatus], [PterodactylInstance.authState])
/// are intentionally not part of this DTO — they are re-derived each
/// session, never persisted.
class InstanceLocalDto {
  const InstanceLocalDto({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.panelVersion,
  });

  final String id;
  final String name;
  final String baseUrl;
  final String? panelVersion;

  factory InstanceLocalDto.fromInstance(PterodactylInstance instance) {
    return InstanceLocalDto(
      id: instance.id,
      name: instance.name,
      baseUrl: instance.baseUrl,
      panelVersion: instance.panelVersion,
    );
  }

  factory InstanceLocalDto.fromJson(Map<String, dynamic> json) {
    return InstanceLocalDto(
      id: json['id'] as String,
      name: json['name'] as String,
      baseUrl: json['baseUrl'] as String,
      panelVersion: json['panelVersion'] as String?,
    );
  }

  PterodactylInstance toInstance() {
    return PterodactylInstance(id: id, name: name, baseUrl: baseUrl, panelVersion: panelVersion);
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'baseUrl': baseUrl,
      if (panelVersion != null) 'panelVersion': panelVersion,
    };
  }
}
