import 'package:meta/meta.dart';

import '../../../core/error/app_exception.dart';
import '../domain/file_repository.dart';

enum FileTransferDirection { upload, download }

enum FileTransferStatus { inProgress, success, failed, cancelled }

/// One upload or download in flight (or just finished) — tracked
/// separately from [FileEntry]/directory listing state (see
/// `FileManagerState.transfers`) because a transfer is not "a file", it
/// is a *process* that may or may not end up producing/reading one, and
/// the UI needs to show several of these concurrently regardless of
/// which directory is currently open (see the task's "upload file A ↓
/// file B nadal można otworzyć" requirement).
@immutable
class FileTransferTask {
  const FileTransferTask({
    required this.id,
    required this.direction,
    required this.fileName,
    required this.status,
    this.transferred = 0,
    this.total,
    this.error,
    this.handle,
  });

  final String id;
  final FileTransferDirection direction;
  final String fileName;
  final FileTransferStatus status;
  final int transferred;

  /// `null` if the server did not report a size — show an indeterminate
  /// indicator rather than a fabricated percentage.
  final int? total;

  final AppException? error;

  /// `null` once the transfer has reached a terminal status — nothing
  /// left to cancel.
  final FileTransferHandle? handle;

  double? get progress => (total == null || total == 0) ? null : transferred / total!;

  FileTransferTask copyWith({
    FileTransferStatus? status,
    int? transferred,
    int? total,
    AppException? error,
    bool clearHandle = false,
  }) {
    return FileTransferTask(
      id: id,
      direction: direction,
      fileName: fileName,
      status: status ?? this.status,
      transferred: transferred ?? this.transferred,
      total: total ?? this.total,
      error: error ?? this.error,
      handle: clearHandle ? null : handle,
    );
  }
}
