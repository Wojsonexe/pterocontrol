import 'package:dio/dio.dart' show CancelToken;

import '../../../core/network/pterodactyl_api_client.dart';
import '../domain/file_entry.dart';
import '../domain/file_repository.dart';
import 'file_entry_dto.dart';
import 'files_api.dart';

/// [FileRepository] backed by [FilesApi] (the JSON-in/JSON-out Files
/// endpoints) and [PterodactylApiClient] directly (for the
/// signed-URL-then-transfer upload/download flow — see [upload]/
/// [download], and `FilesApi.getDownloadUrl`/`getUploadUrl`'s doc
/// comments for why that needs the client, not just [FilesApi]).
///
/// This is the boundary where the `Result<T>` returned by
/// [FilesApi]/[PterodactylApiClient] gets translated into the throw-based
/// convention the rest of the app's repositories use — see
/// `ServerRepositoryImpl`'s identical role.
///
/// **Path convention this class assumes** (Client API `root` + relative
/// `files`/`from`/`to` parameters — see `FilesApi.rename`): every mutating
/// call below passes `root: '/'` and strips the leading `/` from each
/// [FileEntry.path] to get the root-relative path Wings expects. This
/// keeps every path this class hands to the API self-consistent
/// regardless of which two directories a move spans, without needing to
/// compute a "common ancestor" between source and destination.
class FileRepositoryImpl implements FileRepository {
  FileRepositoryImpl({
    required FilesApi api,
    required PterodactylApiClient client,
    required String serverIdentifier,
  })  : _api = api,
        _client = client,
        _serverIdentifier = serverIdentifier;

  final FilesApi _api;
  final PterodactylApiClient _client;
  final String _serverIdentifier;

  static String _relative(String absolutePath) => absolutePath.startsWith('/') ? absolutePath.substring(1) : absolutePath;

  static String _basename(String path) {
    final trimmed = path.endsWith('/') && path != '/' ? path.substring(0, path.length - 1) : path;
    final lastSlash = trimmed.lastIndexOf('/');
    return lastSlash < 0 ? trimmed : trimmed.substring(lastSlash + 1);
  }

  FileEntry _toDomain(FileEntryDto dto, String directory) {
    return FileEntry(
      name: dto.name,
      path: joinFilePath(directory, dto.name),
      isFile: dto.isFile,
      isSymlink: dto.isSymlink,
      size: dto.size,
      mimeType: dto.mimetype,
      modifiedAt: dto.modifiedAt,
    );
  }

  @override
  Future<List<FileEntry>> listDirectory(String path) async {
    final result = await _api.list(_serverIdentifier, directory: path);
    return result.fold(
      onSuccess: (dtos) => dtos.map((dto) => _toDomain(dto, path)).toList(growable: false),
      onFailure: (error) => throw error,
    );
  }

  @override
  Future<String> readFile(String path) async {
    final result = await _api.getContents(_serverIdentifier, file: path);
    return result.fold(onSuccess: (content) => content, onFailure: (error) => throw error);
  }

  @override
  Future<void> writeFile(String path, String content) async {
    final result = await _api.writeContents(_serverIdentifier, file: path, content: content);
    return result.fold(onSuccess: (_) {}, onFailure: (error) => throw error);
  }

  @override
  Future<void> createFolder(String parentPath, String name) async {
    final result = await _api.createFolder(_serverIdentifier, root: parentPath, name: name);
    return result.fold(onSuccess: (_) {}, onFailure: (error) => throw error);
  }

  @override
  Future<void> rename(String path, String newName) async {
    final from = _relative(path);
    final to = _relative(joinFilePath(parentFilePath(path), newName));
    final result = await _api.rename(_serverIdentifier, root: '/', files: [(from: from, to: to)]);
    return result.fold(onSuccess: (_) {}, onFailure: (error) => throw error);
  }

  @override
  Future<void> move(List<String> paths, String destinationDirectory) async {
    final files = [
      for (final path in paths)
        (from: _relative(path), to: _relative(joinFilePath(destinationDirectory, _basename(path)))),
    ];
    final result = await _api.rename(_serverIdentifier, root: '/', files: files);
    return result.fold(onSuccess: (_) {}, onFailure: (error) => throw error);
  }

  @override
  Future<void> copyFile(String path) async {
    final result = await _api.copy(_serverIdentifier, location: _relative(path));
    return result.fold(onSuccess: (_) {}, onFailure: (error) => throw error);
  }

  @override
  Future<FileEntry> compress(String parentPath, List<String> paths) async {
    final result = await _api.compress(
      _serverIdentifier,
      root: parentPath,
      files: [for (final path in paths) _basename(path)],
    );
    return result.fold(onSuccess: (dto) => _toDomain(dto, parentPath), onFailure: (error) => throw error);
  }

  @override
  Future<void> decompress(String archivePath) async {
    final result = await _api.decompress(
      _serverIdentifier,
      root: parentFilePath(archivePath),
      file: _basename(archivePath),
    );
    return result.fold(onSuccess: (_) {}, onFailure: (error) => throw error);
  }

  @override
  Future<void> delete(List<String> paths) async {
    // Every path passed together must share a parent for a single `root`
    // + relative-`files` request to express them all in one call — true
    // for every real caller (multi-select deletion always operates
    // within one open directory). A cross-directory batch would need
    // grouping by parent first; not needed by anything in this app today.
    final root = paths.isEmpty ? '/' : parentFilePath(paths.first);
    final result = await _api.delete(_serverIdentifier, root: root, files: [for (final p in paths) _basename(p)]);
    return result.fold(onSuccess: (_) {}, onFailure: (error) => throw error);
  }

  @override
  FileTransfer upload({
    required String directory,
    required String localFilePath,
    required String fileName,
    FileTransferProgress? onProgress,
  }) {
    final cancelToken = CancelToken();
    final done = _upload(directory, localFilePath, fileName, onProgress, cancelToken);
    return (done: done, handle: _DioFileTransferHandle(cancelToken));
  }

  Future<void> _upload(
    String directory,
    String localFilePath,
    String fileName,
    FileTransferProgress? onProgress,
    CancelToken cancelToken,
  ) async {
    final urlResult = await _api.getUploadUrl(_serverIdentifier);
    final url = urlResult.fold(onSuccess: (u) => u, onFailure: (error) => throw error);

    final uploadResult = await _client.uploadMultipart(
      url: url,
      fieldName: 'files',
      filePath: localFilePath,
      fileName: fileName,
      cancelToken: cancelToken,
      onSendProgress: onProgress == null ? null : (sent, total) => onProgress(sent, total),
    );
    return uploadResult.fold(onSuccess: (_) {}, onFailure: (error) => throw error);
  }

  @override
  FileTransfer download({
    required String path,
    required String savePath,
    FileTransferProgress? onProgress,
  }) {
    final cancelToken = CancelToken();
    final done = _download(path, savePath, onProgress, cancelToken);
    return (done: done, handle: _DioFileTransferHandle(cancelToken));
  }

  Future<void> _download(
    String path,
    String savePath,
    FileTransferProgress? onProgress,
    CancelToken cancelToken,
  ) async {
    final urlResult = await _api.getDownloadUrl(_serverIdentifier, file: path);
    final url = urlResult.fold(onSuccess: (u) => u, onFailure: (error) => throw error);

    final downloadResult = await _client.download(
      url: url,
      savePath: savePath,
      cancelToken: cancelToken,
      onReceiveProgress: onProgress == null ? null : (received, total) => onProgress(received, total),
    );
    return downloadResult.fold(onSuccess: (_) {}, onFailure: (error) => throw error);
  }
}

class _DioFileTransferHandle implements FileTransferHandle {
  _DioFileTransferHandle(this._cancelToken);

  final CancelToken _cancelToken;

  @override
  void cancel() {
    if (!_cancelToken.isCancelled) _cancelToken.cancel('cancelled by user');
  }
}
