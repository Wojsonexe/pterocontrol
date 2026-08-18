import 'package:meta/meta.dart';

import '../../../core/error/app_exception.dart';

enum FileEditorLoadStatus { loading, loaded, error }

enum FileEditorSaveStatus { idle, saving, saved, error }

/// State for one open file in the built-in text editor —
/// `FileEditorController`'s counterpart to `FileManagerState`.
@immutable
class FileEditorState {
  const FileEditorState({
    required this.loadStatus,
    this.loadError,
    this.originalContent,
    this.currentContent,
    this.saveStatus = FileEditorSaveStatus.idle,
    this.saveError,
  });

  static const initial = FileEditorState(loadStatus: FileEditorLoadStatus.loading);

  final FileEditorLoadStatus loadStatus;
  final AppException? loadError;

  /// The content as last confirmed on the server — either just loaded, or
  /// just successfully saved. `null` until the first load succeeds.
  final String? originalContent;

  /// The content as currently shown/edited in the text field. `null`
  /// until the first load succeeds (same moment [originalContent] stops
  /// being `null` — they always start equal).
  final String? currentContent;

  final FileEditorSaveStatus saveStatus;
  final AppException? saveError;

  /// Whether [currentContent] differs from [originalContent] — the sole
  /// source of truth for "unsaved changes" (see the task's requirement),
  /// never a separately-tracked boolean that could drift from the actual
  /// text.
  bool get isDirty => currentContent != null && originalContent != null && currentContent != originalContent;

  FileEditorState copyWith({
    FileEditorLoadStatus? loadStatus,
    AppException? loadError,
    bool clearLoadError = false,
    String? originalContent,
    String? currentContent,
    FileEditorSaveStatus? saveStatus,
    AppException? saveError,
    bool clearSaveError = false,
  }) {
    return FileEditorState(
      loadStatus: loadStatus ?? this.loadStatus,
      loadError: clearLoadError ? null : (loadError ?? this.loadError),
      originalContent: originalContent ?? this.originalContent,
      currentContent: currentContent ?? this.currentContent,
      saveStatus: saveStatus ?? this.saveStatus,
      saveError: clearSaveError ? null : (saveError ?? this.saveError),
    );
  }
}
