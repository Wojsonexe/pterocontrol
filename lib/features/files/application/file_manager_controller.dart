import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/error/app_exception.dart';
import '../domain/file_entry.dart';
import '../domain/file_repository.dart';
import '../domain/file_target.dart';
import 'file_manager_state.dart';
import 'file_transfer_task.dart';
import 'files_providers.dart';

const _uuid = Uuid();

/// Drives one server's file manager for the UI: lists/navigates
/// directories, runs mutations (create/rename/move/copy/delete/
/// compress/decompress), and tracks uploads/downloads — all through
/// [FileRepository], never inventing a second store for any of it.
///
/// Scoped by [FileTarget] (`.family`), `autoDispose`: leaving the Files
/// tab tears this down, which cancels any transfer still in flight (see
/// [build]'s `ref.onDispose`) — the same "no background work for a
/// screen nobody is looking at" rule `ConsoleRepository` already follows
/// for the WebSocket connection.
class FileManagerController extends Notifier<FileManagerState> {
  FileManagerController(this.target);

  final FileTarget target;

  FileRepository get _repository => ref.read(fileRepositoryProvider(target));

  /// Every transfer handle currently cancellable — tracked as a plain
  /// field, deliberately **not** read from `state` inside [build]'s
  /// `ref.onDispose` below: reading `state` (which goes through `ref`
  /// internally) during a dispose callback is itself invalid Riverpod
  /// usage ("Cannot use Ref or modify other providers inside
  /// lifecycles"), so this needs its own plain-Dart bookkeeping instead.
  final Set<FileTransferHandle> _activeHandles = {};

  @override
  FileManagerState build() {
    final initial = FileManagerState.initial('/');
    ref.onDispose(() {
      for (final handle in _activeHandles) {
        handle.cancel();
      }
    });
    // `announceStart: false` — the initial [FileManagerState] returned
    // below already *is* the "loading" state `_load` would otherwise
    // synchronously write first; doing that write here would run before
    // `build()` has returned (Riverpod has not finished constructing this
    // provider yet), which is exactly the "modify state during its own
    // build" mistake `ServerRuntimeSyncController`/`ConsoleController`
    // avoid by never touching `state` before their own first `await`.
    unawaited(_load('/', isInitialLoad: true, announceStart: false));
    return initial;
  }

  /// Opens [path] as a *new* directory context — clears the previous
  /// listing/selection rather than keeping it visible while loading (this
  /// is a different directory, not a refresh of the current one; see
  /// [refresh] for that case).
  Future<void> navigateTo(String path) async {
    if (!ref.mounted || path == state.currentPath) return;
    state = FileManagerState(currentPath: path, transfers: state.transfers);
    await _load(path, isInitialLoad: true);
  }

  Future<void> goUp() async {
    if (state.currentPath == '/') return;
    await navigateTo(parentFilePath(state.currentPath));
  }

  /// Re-fetches the *current* directory — unlike [navigateTo], the
  /// previously loaded [FileManagerState.entries] stay on screen the
  /// whole time (see [FileManagerState.isRefreshing]'s doc comment) —
  /// pull-to-refresh must never blank the list while it runs.
  Future<void> refresh() => _load(state.currentPath, isInitialLoad: false);

  Future<void> _load(String path, {required bool isInitialLoad, bool announceStart = true}) async {
    if (!ref.mounted) return;
    if (announceStart) {
      state = state.copyWith(
        status: isInitialLoad ? FileManagerLoadStatus.loading : state.status,
        isRefreshing: !isInitialLoad,
        clearError: true,
      );
    }
    try {
      final entries = await _repository.listDirectory(path);
      if (!ref.mounted) return;
      final sorted = _sorted(entries);
      final stillPresent = sorted.map((e) => e.path).toSet();
      state = state.copyWith(
        currentPath: path,
        entries: sorted,
        status: FileManagerLoadStatus.loaded,
        isRefreshing: false,
        selectedPaths: state.selectedPaths.intersection(stillPresent),
        clearError: true,
      );
    } catch (error) {
      if (!ref.mounted) return;
      final appError = error is AppException ? error : UnknownException(cause: error);
      if (state.entries.isEmpty) {
        state = state.copyWith(status: FileManagerLoadStatus.error, error: appError, isRefreshing: false);
      } else {
        // A refresh failed but stale entries are already on screen —
        // keep showing them (see `FileManagerState.error`'s doc comment)
        // rather than replacing a working view with a full-screen error.
        state = state.copyWith(isRefreshing: false, error: appError);
      }
    }
  }

  List<FileEntry> _sorted(List<FileEntry> entries) {
    final sorted = [...entries];
    sorted.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return sorted;
  }

  // --- Selection -----------------------------------------------------

  void toggleSelection(String path) {
    final next = {...state.selectedPaths};
    if (!next.remove(path)) next.add(path);
    state = state.copyWith(selectedPaths: next);
  }

  void clearSelection() => state = state.copyWith(selectedPaths: const {});

  void selectAll() => state = state.copyWith(selectedPaths: state.entries.map((e) => e.path).toSet());

  // --- Mutations -------------------------------------------------------
  //
  // Each of these marks the affected path(s) busy for the duration (so
  // only *that* row shows a spinner — see `FileManagerState.busyPaths`),
  // and on success patches `state.entries` directly instead of doing a
  // full `_load` wherever the result is fully knowable locally (rename,
  // delete, move) — see the task's "DELETE → API success → natychmiastowa
  // aktualizacja lokalnego state" requirement. Where the result is *not*
  // fully knowable client-side (a new folder/file's real attributes, a
  // copy's server-chosen name, an archive's size, decompressed contents),
  // this falls back to a targeted `_load` of the current directory —
  // still not a "wait, then reload" for the ones that do not need it.

  Future<void> createFolder(String name) => _runAndReload(() => _repository.createFolder(state.currentPath, name));

  Future<void> createFile(String name) =>
      _runAndReload(() => _repository.writeFile(joinFilePath(state.currentPath, name), ''));

  Future<void> copyEntry(String path) => _runBusyAndReload(path, FileOperationKind.copying, () => _repository.copyFile(path));

  Future<void> decompressEntry(String path) =>
      _runBusyAndReload(path, FileOperationKind.decompressing, () => _repository.decompress(path));

  Future<void> compressSelected() async {
    final paths = state.selectedPaths.toList(growable: false);
    if (paths.isEmpty) return;
    await _runBusyMultiAndReload(paths, FileOperationKind.compressing, () async {
      await _repository.compress(state.currentPath, paths);
    });
  }

  Future<void> rename(String path, String newName) async {
    state = state.copyWith(busyPaths: {...state.busyPaths, path: FileOperationKind.renaming});
    try {
      await _repository.rename(path, newName);
      if (!ref.mounted) return;
      final newPath = joinFilePath(parentFilePath(path), newName);
      state = state.copyWith(
        entries: _sorted([
          for (final e in state.entries)
            if (e.path == path) e.copyWith(name: newName, path: newPath) else e,
        ]),
        busyPaths: _without(state.busyPaths, {path}),
      );
    } catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(busyPaths: _without(state.busyPaths, {path}), error: _asAppException(error));
    }
  }

  Future<void> deleteEntries(List<String> paths) async {
    if (paths.isEmpty) return;
    state = state.copyWith(busyPaths: {for (final p in paths) p: FileOperationKind.deleting, ...state.busyPaths});
    try {
      await _repository.delete(paths);
      if (!ref.mounted) return;
      final removed = paths.toSet();
      state = state.copyWith(
        entries: [for (final e in state.entries) if (!removed.contains(e.path)) e],
        selectedPaths: state.selectedPaths.difference(removed),
        busyPaths: _without(state.busyPaths, removed),
      );
    } catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(busyPaths: _without(state.busyPaths, paths.toSet()), error: _asAppException(error));
    }
  }

  Future<void> moveEntries(List<String> paths, String destinationDirectory) async {
    if (paths.isEmpty) return;
    state = state.copyWith(busyPaths: {for (final p in paths) p: FileOperationKind.moving, ...state.busyPaths});
    try {
      await _repository.move(paths, destinationDirectory);
      if (!ref.mounted) return;
      final moved = paths.toSet();
      state = state.copyWith(
        // Moved *out of* the currently open directory (the only kind of
        // move this screen can start, since every source path is
        // something currently listed) — drop them from view; there is
        // nothing to patch them *to* here, the destination is a
        // different `FileManagerController` instance (or the same one,
        // later, if the user navigates there — a fresh `_load` covers
        // that normally).
        entries: [for (final e in state.entries) if (!moved.contains(e.path)) e],
        selectedPaths: state.selectedPaths.difference(moved),
        busyPaths: _without(state.busyPaths, moved),
      );
    } catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(busyPaths: _without(state.busyPaths, paths.toSet()), error: _asAppException(error));
    }
  }

  Future<void> _runAndReload(Future<void> Function() action) async {
    try {
      await action();
      if (!ref.mounted) return;
      await _load(state.currentPath, isInitialLoad: false);
    } catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(error: _asAppException(error));
    }
  }

  Future<void> _runBusyAndReload(String path, FileOperationKind kind, Future<void> Function() action) =>
      _runBusyMultiAndReload([path], kind, action);

  Future<void> _runBusyMultiAndReload(List<String> paths, FileOperationKind kind, Future<void> Function() action) async {
    state = state.copyWith(busyPaths: {for (final p in paths) p: kind, ...state.busyPaths});
    try {
      await action();
      if (!ref.mounted) return;
      await _load(state.currentPath, isInitialLoad: false);
      if (!ref.mounted) return;
      state = state.copyWith(busyPaths: _without(state.busyPaths, paths.toSet()));
    } catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(busyPaths: _without(state.busyPaths, paths.toSet()), error: _asAppException(error));
    }
  }

  Map<String, FileOperationKind> _without(Map<String, FileOperationKind> map, Set<String> paths) {
    return {for (final entry in map.entries) if (!paths.contains(entry.key)) entry.key: entry.value};
  }

  AppException _asAppException(Object error) => error is AppException ? error : UnknownException(cause: error);

  // --- Transfers (upload/download) -------------------------------------

  /// Starts uploading [localFilePath] into the currently open directory
  /// as [fileName]. Returns the transfer's id (for [cancelTransfer]).
  String startUpload({required String localFilePath, required String fileName}) {
    final id = _uuid.v4();
    final transfer = _repository.upload(
      directory: state.currentPath,
      localFilePath: localFilePath,
      fileName: fileName,
      onProgress: (transferred, total) => _updateTransferProgress(id, transferred, total),
    );
    _activeHandles.add(transfer.handle);
    state = state.copyWith(transfers: [
      FileTransferTask(
        id: id,
        direction: FileTransferDirection.upload,
        fileName: fileName,
        status: FileTransferStatus.inProgress,
        handle: transfer.handle,
      ),
      ...state.transfers,
    ]);
    unawaited(
      transfer.done.then(
        (_) => _finishTransfer(id, FileTransferStatus.success, onDone: () => unawaited(refresh())),
        onError: (Object error) => _finishTransfer(
          id,
          error is CancelledException ? FileTransferStatus.cancelled : FileTransferStatus.failed,
          error: _asAppException(error),
        ),
      ),
    );
    return id;
  }

  /// Starts downloading [entry] to [savePath] (already resolved by the
  /// caller — e.g. via a native "save as" picker; this controller has no
  /// platform/file-system-location concerns of its own). Returns the
  /// transfer's id.
  String startDownload({required FileEntry entry, required String savePath}) {
    final id = _uuid.v4();
    final transfer = _repository.download(
      path: entry.path,
      savePath: savePath,
      onProgress: (transferred, total) => _updateTransferProgress(id, transferred, total),
    );
    _activeHandles.add(transfer.handle);
    state = state.copyWith(transfers: [
      FileTransferTask(
        id: id,
        direction: FileTransferDirection.download,
        fileName: entry.name,
        status: FileTransferStatus.inProgress,
        total: entry.size,
        handle: transfer.handle,
      ),
      ...state.transfers,
    ]);
    unawaited(
      transfer.done.then(
        (_) => _finishTransfer(id, FileTransferStatus.success),
        onError: (Object error) => _finishTransfer(
          id,
          error is CancelledException ? FileTransferStatus.cancelled : FileTransferStatus.failed,
          error: _asAppException(error),
        ),
      ),
    );
    return id;
  }

  void cancelTransfer(String id) {
    for (final transfer in state.transfers) {
      if (transfer.id == id) {
        transfer.handle?.cancel();
        return;
      }
    }
  }

  void dismissTransfer(String id) {
    state = state.copyWith(transfers: [for (final t in state.transfers) if (t.id != id) t]);
  }

  void _updateTransferProgress(String id, int transferred, int total) {
    if (!ref.mounted) return;
    state = state.copyWith(transfers: [
      for (final t in state.transfers)
        if (t.id == id) t.copyWith(transferred: transferred, total: total >= 0 ? total : null) else t,
    ]);
  }

  void _finishTransfer(String id, FileTransferStatus status, {AppException? error, void Function()? onDone}) {
    if (!ref.mounted) return;
    for (final t in state.transfers) {
      if (t.id == id && t.handle != null) _activeHandles.remove(t.handle);
    }
    state = state.copyWith(transfers: [
      for (final t in state.transfers) if (t.id == id) t.copyWith(status: status, error: error, clearHandle: true) else t,
    ]);
    onDone?.call();
  }
}

final fileManagerControllerProvider =
    NotifierProvider.autoDispose.family<FileManagerController, FileManagerState, FileTarget>(
  FileManagerController.new,
);
