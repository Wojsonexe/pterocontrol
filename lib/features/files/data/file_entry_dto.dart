/// Raw shape of one entry's `attributes` object from the Pterodactyl
/// Client API's `GET .../files/list` (each item in the `data` array, per
/// the standard `PterodactylEnvelope` list shape — same convention
/// `ServerDto` follows for `GET /api/client`).
///
/// Mirrors the JSON field names/types exactly. No `path`/`directory`
/// field exists here — the API only ever returns a bare [name] per
/// entry, scoped to whatever directory was requested; see
/// `FileEntry`/`joinFilePath` for how the domain layer reconstructs a
/// full path.
class FileEntryDto {
  const FileEntryDto({
    required this.name,
    required this.size,
    required this.isFile,
    required this.isSymlink,
    required this.mimetype,
    required this.modifiedAt,
  });

  final String name;
  final int size;
  final bool isFile;
  final bool isSymlink;
  final String? mimetype;
  final DateTime modifiedAt;

  factory FileEntryDto.fromJson(Map<String, dynamic> json) {
    final modifiedRaw = json['modified_at'] as String?;
    return FileEntryDto(
      name: json['name'] as String,
      size: (json['size'] as num?)?.toInt() ?? 0,
      isFile: json['is_file'] as bool? ?? false,
      isSymlink: json['is_symlink'] as bool? ?? false,
      mimetype: json['mimetype'] as String?,
      // Falls back to "now" rather than throwing on a missing/malformed
      // timestamp — a file listing must not fail to render entirely over
      // one entry's unparseable date; see `FileRepositoryImpl.list`.
      modifiedAt: modifiedRaw == null ? DateTime.now() : DateTime.tryParse(modifiedRaw) ?? DateTime.now(),
    );
  }
}
