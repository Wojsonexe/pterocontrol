import 'package:meta/meta.dart';

/// One entry (file, directory, or symlink) inside a server's filesystem,
/// as reported by the Pterodactyl Client API's
/// `GET .../files/list?directory=...` — see `FileEntryDto` for the raw
/// JSON shape this is built from.
///
/// [path] is **not** part of the API response (Wings only returns a
/// [name] for each entry within the directory that was asked for) — it
/// is computed by the caller (`FileRepositoryImpl.list`) by joining the
/// requested directory with [name], so every [FileEntry] this app ever
/// holds already carries its own full path rather than requiring every
/// caller to reconstruct it from a separately-tracked "current directory".
@immutable
class FileEntry {
  const FileEntry({
    required this.name,
    required this.path,
    required this.isFile,
    required this.isSymlink,
    required this.size,
    required this.mimeType,
    required this.modifiedAt,
  });

  final String name;
  final String path;

  /// `false` means this is a directory. Wings' own API has exactly this
  /// one boolean — there is no separate "is directory" field, and no
  /// third kind beyond file/directory ([isSymlink] is orthogonal: a
  /// symlink can point at either).
  final bool isFile;

  final bool isSymlink;

  bool get isDirectory => !isFile;

  /// Bytes. `0` for a directory (Wings does not report a directory's
  /// recursive size — this is not "empty", it is simply not measured).
  final int size;

  final String? mimeType;
  final DateTime modifiedAt;

  /// A dotfile (`.env`, `.gitignore`, ...) — a client-side convenience,
  /// **not** an API concept. Pterodactyl's Files API has no "hidden"
  /// flag; Wings' directory listing always includes every entry,
  /// dotfiles included. Exists so the UI can de-emphasize (never hide —
  /// see the task's "hidden files jeżeli API je obsługuje": it does not,
  /// so nothing is ever actually hidden) these the way most desktop file
  /// managers visually do.
  bool get isDotfile => name.startsWith('.');

  /// Whether this looks like a plain-text file worth offering to open in
  /// the built-in editor, based on [name]'s extension — Wings/the Client
  /// API does not classify "editable" for us, so this is a client-side
  /// heuristic over a real, bounded allow-list (see
  /// `FileEditorController`'s doc comment for the exact list), never a
  /// guess based on [mimeType] alone (a `text/plain` mimetype from Wings
  /// is itself just a `net/http`-style sniff of the first few hundred
  /// bytes, not authoritative for e.g. a `.jar` that happens to start
  /// with ASCII).
  static const editableExtensions = {
    'txt', 'log', 'json', 'yaml', 'yml', 'xml', 'properties', 'ini', 'conf', 'cfg', 'toml', 'env', //
    'md', 'sh', 'bat', 'cmd', 'gitignore', 'dockerignore', 'js', 'ts', 'py', 'lua', 'sql', 'css', 'html',
  };

  String get _extension {
    final dot = name.lastIndexOf('.');
    // A dotfile with no further extension (".env") is matched on its
    // full name below `_extension`; `lastIndexOf('.') == 0` here means
    // "no extension after the leading dot", not "no dot at all".
    if (dot <= 0) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  bool get isEditable {
    if (!isFile) return false;
    final ext = _extension;
    if (ext.isNotEmpty && editableExtensions.contains(ext)) return true;
    // Files that *are* their own extension, dotfile-style
    // (".gitignore", ".env", ".dockerignore" with no further suffix).
    return editableExtensions.contains(name.toLowerCase());
  }

  FileEntry copyWith({String? name, String? path}) {
    return FileEntry(
      name: name ?? this.name,
      path: path ?? this.path,
      isFile: isFile,
      isSymlink: isSymlink,
      size: size,
      mimeType: mimeType,
      modifiedAt: modifiedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is FileEntry &&
        other.name == name &&
        other.path == path &&
        other.isFile == isFile &&
        other.isSymlink == isSymlink &&
        other.size == size &&
        other.mimeType == mimeType &&
        other.modifiedAt == modifiedAt;
  }

  @override
  int get hashCode => Object.hash(name, path, isFile, isSymlink, size, mimeType, modifiedAt);

  @override
  String toString() => 'FileEntry(path: $path, isFile: $isFile, size: $size)';
}

/// Joins a directory and an entry name into a normalized path — always
/// `/`-separated (Wings' own convention, regardless of host OS), never a
/// double slash, and always rooted (`/` prefix), matching what the Files
/// API's `directory`/`root`/`file` query parameters expect.
String joinFilePath(String directory, String name) {
  final normalizedDir = directory.endsWith('/') ? directory : '$directory/';
  return normalizedDir == '/' ? '/$name' : '$normalizedDir$name';
}

/// The parent of [path] ("/" for anything directly under root, and "/"
/// for "/" itself — there is no parent above root).
String parentFilePath(String path) {
  final trimmed = path.endsWith('/') && path != '/' ? path.substring(0, path.length - 1) : path;
  final lastSlash = trimmed.lastIndexOf('/');
  if (lastSlash <= 0) return '/';
  return trimmed.substring(0, lastSlash);
}
