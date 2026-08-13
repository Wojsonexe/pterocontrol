/// Decodes the Fractal-based envelope every Pterodactyl Client API response
/// uses: a single resource is `{"object": "...", "attributes": {...}}`, a
/// collection is `{"object": "list", "data": [...]}` with paging info under
/// `meta.pagination`.
///
/// This is deliberately still endpoint-agnostic — it knows the *shape*
/// every Pterodactyl response follows, not what a "server" or a "backup"
/// is. Endpoint-specific API classes (e.g. `ServersApi`) use this to get
/// from a raw JSON body to a list of attribute maps, then parse those into
/// their own DTOs.
abstract final class PterodactylEnvelope {
  /// Unwraps a single-resource response and returns its `attributes`.
  static Map<String, dynamic> unwrapItem(dynamic json) {
    if (json is! Map<String, dynamic> || json['attributes'] is! Map<String, dynamic>) {
      throw const FormatException(
        'Expected a Pterodactyl item envelope with an "attributes" object.',
      );
    }
    return json['attributes'] as Map<String, dynamic>;
  }

  /// Unwraps a collection response into each item's `attributes` and,
  /// when present, [PaginationMeta].
  static (List<Map<String, dynamic>> items, PaginationMeta? meta) unwrapList(dynamic json) {
    if (json is! Map<String, dynamic> || json['data'] is! List) {
      throw const FormatException('Expected a Pterodactyl list envelope with a "data" array.');
    }

    final items = (json['data'] as List)
        .map((entry) => unwrapItem(entry))
        .toList(growable: false);

    final metaJson = json['meta'];
    final meta = metaJson is Map<String, dynamic> ? PaginationMeta.fromJson(metaJson) : null;

    return (items, meta);
  }
}

/// Pagination info from a Pterodactyl list response's `meta.pagination`.
///
/// Pages are 1-indexed, matching the Pterodactyl Client API's `?page=`
/// query parameter.
class PaginationMeta {
  const PaginationMeta({
    required this.currentPage,
    required this.totalPages,
    required this.total,
    required this.perPage,
  });

  final int currentPage;
  final int totalPages;
  final int total;
  final int perPage;

  bool get hasNextPage => currentPage < totalPages;

  factory PaginationMeta.fromJson(Map<String, dynamic> json) {
    final pagination = json['pagination'];
    if (pagination is! Map<String, dynamic>) {
      return const PaginationMeta(currentPage: 1, totalPages: 1, total: 0, perPage: 0);
    }
    return PaginationMeta(
      currentPage: (pagination['current_page'] as num?)?.toInt() ?? 1,
      totalPages: (pagination['total_pages'] as num?)?.toInt() ?? 1,
      total: (pagination['total'] as num?)?.toInt() ?? 0,
      perPage: (pagination['per_page'] as num?)?.toInt() ?? 0,
    );
  }
}
