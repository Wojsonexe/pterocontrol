import 'package:meta/meta.dart';

import '../../../core/error/app_exception.dart';
import '../domain/file_entry.dart';
import 'file_transfer_task.dart';

enum FileManagerLoadStatus { loading, loaded, error }

/// What a specific, already-listed entry is currently in the middle of —
/// drives that single row's own inline indicator without touching any
/// other row (see the task's "dla pojedynczych operacji nie blokuj
/// całego File Managera").
enum FileOperationKind { deleting, renaming, moving, copying, compressing, decompressing }

/// Everything `FileManagerController` exposes to the UI for one server's
/// file manager session: the currently open directory, its listing, and
/// the state of every in-progress operation (per-entry and transfers)
/// layered on top of it — bundled together the same way `ConsoleState`
/// bundles connection/runtime/events, because the UI always needs all of
/// it at once to render one coherent screen.
@immutable
class FileManagerState {
  const FileManagerState({
    required this.currentPath,
    this.entries = const [],
    this.status = FileManagerLoadStatus.loading,
    this.error,
    this.isRefreshing = false,
    this.selectedPaths = const {},
    this.busyPaths = const {},
    this.transfers = const [],
  });

  factory FileManagerState.initial(String rootPath) => FileManagerState(currentPath: rootPath);

  /// Absolute, `/`-rooted path of the directory currently open.
  final String currentPath;

  /// This directory's entries — directories first, then files, each
  /// group name-sorted case-insensitively (see
  /// `FileManagerController._sorted`). Stays as the *last successfully
  /// loaded* listing during [isRefreshing] — never cleared just because
  /// a refresh is in flight (same "stale-while-refresh" rule
  /// `ServerRuntimeSyncState` already applies to runtime metrics).
  final List<FileEntry> entries;

  final FileManagerLoadStatus status;

  /// Set only when [status] is [FileManagerLoadStatus.error] *and* there
  /// is no previously-loaded [entries] to fall back to showing — a
  /// refresh that fails while stale entries are already on screen keeps
  /// [status] at [FileManagerLoadStatus.loaded] and surfaces this
  /// instead as [isRefreshing] going false with a snackbar-style error,
  /// not a full-screen error state; see `FileManagerController._load`.
  final AppException? error;

  final bool isRefreshing;

  final Set<String> selectedPaths;

  bool get isSelecting => selectedPaths.isNotEmpty;

  /// Path -> what that entry is currently doing. An entry absent here is
  /// idle, regardless of whether *other* entries are busy.
  final Map<String, FileOperationKind> busyPaths;

  /// Every upload/download this session has started, most recent first —
  /// completed/failed/cancelled ones stay until [FileManagerController]
  /// dismisses them (or the controller itself is disposed), so the user
  /// can see what just happened, not just what is still running.
  final List<FileTransferTask> transfers;

  List<FileTransferTask> get activeTransfers =>
      transfers.where((t) => t.status == FileTransferStatus.inProgress).toList(growable: false);

  FileManagerState copyWith({
    String? currentPath,
    List<FileEntry>? entries,
    FileManagerLoadStatus? status,
    AppException? error,
    bool clearError = false,
    bool? isRefreshing,
    Set<String>? selectedPaths,
    Map<String, FileOperationKind>? busyPaths,
    List<FileTransferTask>? transfers,
  }) {
    return FileManagerState(
      currentPath: currentPath ?? this.currentPath,
      entries: entries ?? this.entries,
      status: status ?? this.status,
      error: clearError ? null : (error ?? this.error),
      isRefreshing: isRefreshing ?? this.isRefreshing,
      selectedPaths: selectedPaths ?? this.selectedPaths,
      busyPaths: busyPaths ?? this.busyPaths,
      transfers: transfers ?? this.transfers,
    );
  }
}
