import 'dart:async';

import 'package:pterodactyl_mobile/core/error/app_exception.dart';
import 'package:pterodactyl_mobile/features/files/domain/file_entry.dart';
import 'package:pterodactyl_mobile/features/files/domain/file_repository.dart';

/// Controllable [FileRepository] for controller-level tests — real logic
/// (`FileManagerController`/`FileEditorController`) exercised against
/// this fake's scripted responses, not a mock that just echoes back
/// whatever it was told to return.
class FakeFileRepository implements FileRepository {
  /// directory path -> entries to return from [listDirectory].
  Map<String, List<FileEntry>> directories = {};

  /// directory path -> error to throw from [listDirectory] instead.
  Map<String, AppException> listErrors = {};

  /// path -> file contents for [readFile].
  Map<String, String> fileContents = {};

  AppException? readError;
  AppException? writeError;
  AppException? createFolderError;
  AppException? renameError;
  AppException? moveError;
  AppException? copyError;
  AppException? deleteError;
  AppException? compressError;
  AppException? decompressError;

  final List<String> writeCalls = [];
  final List<({List<String> paths, String destination})> moveCalls = [];
  final List<String> deleteCalls = [];
  int listCallCount = 0;

  /// If set, [listDirectory] waits on this before resolving — lets a
  /// test observe the in-between "loading"/"refreshing" state.
  Completer<void>? listGate;

  @override
  Future<List<FileEntry>> listDirectory(String path) async {
    listCallCount++;
    if (listGate != null) await listGate!.future;
    final error = listErrors[path];
    if (error != null) throw error;
    return directories[path] ?? const [];
  }

  @override
  Future<String> readFile(String path) async {
    if (readError != null) throw readError!;
    return fileContents[path] ?? '';
  }

  @override
  Future<void> writeFile(String path, String content) async {
    writeCalls.add(path);
    if (writeError != null) throw writeError!;
    fileContents[path] = content;
  }

  @override
  Future<void> createFolder(String parentPath, String name) async {
    if (createFolderError != null) throw createFolderError!;
  }

  @override
  Future<void> rename(String path, String newName) async {
    if (renameError != null) throw renameError!;
  }

  @override
  Future<void> move(List<String> paths, String destinationDirectory) async {
    moveCalls.add((paths: paths, destination: destinationDirectory));
    if (moveError != null) throw moveError!;
  }

  @override
  Future<void> copyFile(String path) async {
    if (copyError != null) throw copyError!;
  }

  @override
  Future<FileEntry> compress(String parentPath, List<String> paths) async {
    if (compressError != null) throw compressError!;
    return FileEntry(
      name: 'archive.tar.gz',
      path: joinFilePath(parentPath, 'archive.tar.gz'),
      isFile: true,
      isSymlink: false,
      size: 100,
      mimeType: 'application/gzip',
      modifiedAt: DateTime.now(),
    );
  }

  @override
  Future<void> decompress(String archivePath) async {
    if (decompressError != null) throw decompressError!;
  }

  @override
  Future<void> delete(List<String> paths) async {
    deleteCalls.addAll(paths);
    if (deleteError != null) throw deleteError!;
  }

  Completer<void>? uploadGate;
  AppException? uploadError;
  final List<FakeTransferHandle> uploadHandles = [];

  @override
  FileTransfer upload({
    required String directory,
    required String localFilePath,
    required String fileName,
    FileTransferProgress? onProgress,
  }) {
    final handle = FakeTransferHandle();
    uploadHandles.add(handle);
    final done = () async {
      onProgress?.call(0, 100);
      if (uploadGate != null) await uploadGate!.future;
      if (handle.cancelled) throw const CancelledException();
      if (uploadError != null) throw uploadError!;
      onProgress?.call(100, 100);
    }();
    return (done: done, handle: handle);
  }

  Completer<void>? downloadGate;
  AppException? downloadError;
  final List<FakeTransferHandle> downloadHandles = [];

  @override
  FileTransfer download({
    required String path,
    required String savePath,
    FileTransferProgress? onProgress,
  }) {
    final handle = FakeTransferHandle();
    downloadHandles.add(handle);
    final done = () async {
      onProgress?.call(0, 100);
      if (downloadGate != null) await downloadGate!.future;
      if (handle.cancelled) throw const CancelledException();
      if (downloadError != null) throw downloadError!;
      onProgress?.call(100, 100);
    }();
    return (done: done, handle: handle);
  }
}

class FakeTransferHandle implements FileTransferHandle {
  bool cancelled = false;

  @override
  void cancel() => cancelled = true;
}
