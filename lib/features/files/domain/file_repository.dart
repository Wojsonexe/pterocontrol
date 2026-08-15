import 'file_entry.dart';

/// Progress callback for an upload/download in flight — `transferred`/
/// `total` in bytes, `total` is `-1` if the server did not report a
/// `Content-Length` (matches `dio`'s own `onReceiveProgress`/
/// `onSendProgress` contract, without leaking `dio` itself into this
/// domain-layer interface).
typedef FileTransferProgress = void Function(int transferred, int total);

/// Lets a caller cancel an in-flight upload/download it started. Never
/// implemented against `dio` directly outside `data/` — see
/// [FileRepositoryImpl] for the one place a `CancelToken` actually exists.
abstract interface class FileTransferHandle {
  void cancel();
}

/// A [Future] paired with the [FileTransferHandle] that can cancel it —
/// returned by [FileRepository.upload]/[FileRepository.download] so a
/// caller has both "wait for this to finish" and "let the user cancel
/// it" without the two racing to be constructed separately.
typedef FileTransfer = ({Future<void> done, FileTransferHandle handle});

/// Manages one server's filesystem through the Pterodactyl Client API's
/// Files endpoints.
///
/// A [FileRepository] is scoped to exactly one server on one instance at
/// construction time — same convention as [ServerRepository]/
/// [ConsoleRepository]; no method below takes an instance or server id.
///
/// Every path (both parameters and [FileEntry.path]) is an absolute,
/// `/`-rooted path (`/world/level.dat`), never a bare name and never
/// relative — see `joinFilePath`/`parentFilePath`.
///
/// Implementations translate any transport failure into a thrown
/// [AppException] — callers never see a `Result` or a raw `DioException`,
/// matching [ServerRepository]'s convention exactly.
abstract interface class FileRepository {
  /// Every entry directly inside [path] (not recursive).
  Future<List<FileEntry>> listDirectory(String path);

  /// The full text contents of the file at [path]. Only ever call this
  /// for an entry `FileEntry.isEditable` already said yes to.
  Future<String> readFile(String path);

  /// Overwrites (or creates) the file at [path] with [content].
  Future<void> writeFile(String path, String content);

  Future<void> createFolder(String parentPath, String name);

  /// Renames the entry at [path] to [newName], staying in the same
  /// directory. See [move] for changing directory — both are the Files
  /// API's one `rename` endpoint underneath (see `FilesApi`'s doc
  /// comment); this method exists separately because "rename" and "move"
  /// are different user-facing actions with different UI (a text field
  /// vs. a directory picker), not because the wire call differs.
  Future<void> rename(String path, String newName);

  /// Moves every entry in [paths] into [destinationDirectory], keeping
  /// each entry's own name. One request for the whole batch — see
  /// `FilesApi.rename`'s bulk `files` array.
  Future<void> move(List<String> paths, String destinationDirectory);

  /// Copies the single file at [path]. Wings names the copy itself (a
  /// " copy" suffix) — there is no bulk-copy in the real Files API, so
  /// this deliberately takes one path, not a list; see `FilesApi`'s doc
  /// comment.
  Future<void> copyFile(String path);

  /// Archives [paths] (all direct children of [parentPath]) into one new
  /// `.tar.gz` inside [parentPath], returning the archive's own entry.
  Future<FileEntry> compress(String parentPath, List<String> paths);

  Future<void> decompress(String archivePath);

  /// Deletes every entry in [paths]. One request for the whole batch.
  Future<void> delete(List<String> paths);

  /// Uploads the local file at [localFilePath] into [directory] as
  /// [fileName]. See [FileTransfer]'s doc comment for the
  /// wait-and-cancel shape this returns.
  FileTransfer upload({
    required String directory,
    required String localFilePath,
    required String fileName,
    FileTransferProgress? onProgress,
  });

  /// Downloads the file at [path] to [savePath] on this device, streamed
  /// directly to disk (never buffered fully in memory — see
  /// `PterodactylApiClient.download`).
  FileTransfer download({
    required String path,
    required String savePath,
    FileTransferProgress? onProgress,
  });
}
