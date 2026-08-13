/// Raw shape of one server's `attributes` object from the Pterodactyl
/// Client API (`GET /api/client`, `GET /api/client/servers/{server}`).
///
/// Mirrors the JSON field names/types exactly (including snake_case) —
/// this is the *only* place in the app allowed to know that. Everything
/// above `data/` works with [Server], never with this DTO or raw JSON.
class ServerDto {
  const ServerDto({
    required this.identifier,
    required this.uuid,
    required this.name,
    required this.node,
    required this.status,
    required this.isTransferring,
    required this.memoryMb,
    required this.diskMb,
    required this.cpuPercent,
    this.description,
  });

  final String identifier;
  final String uuid;
  final String name;
  final String? description;
  final String node;

  /// Raw status string, or `null` — see `ServerAdministrativeStatus` in the
  /// domain layer for what these mean. Kept as a raw string here; mapping
  /// to the enum happens in the repository.
  final String? status;

  final bool isTransferring;
  final int memoryMb;
  final int diskMb;
  final int cpuPercent;

  factory ServerDto.fromJson(Map<String, dynamic> json) {
    final limits = json['limits'];
    final limitsMap = limits is Map<String, dynamic> ? limits : const <String, dynamic>{};

    return ServerDto(
      identifier: json['identifier'] as String,
      uuid: json['uuid'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      node: json['node'] as String,
      status: json['status'] as String?,
      isTransferring: json['is_transferring'] as bool? ?? false,
      memoryMb: (limitsMap['memory'] as num?)?.toInt() ?? 0,
      diskMb: (limitsMap['disk'] as num?)?.toInt() ?? 0,
      cpuPercent: (limitsMap['cpu'] as num?)?.toInt() ?? 0,
    );
  }
}
