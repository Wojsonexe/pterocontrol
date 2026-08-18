import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_exception.dart';
import '../domain/file_repository.dart';
import 'file_editor_state.dart';
import 'files_providers.dart';

/// Identifies one open file in the editor — the target's instance/server
/// plus the file's own absolute path.
typedef FileEditorTarget = ({String instanceId, String serverIdentifier, String path});

/// Drives the built-in text editor for one file: loads its contents,
/// tracks unsaved edits, and saves/discards — through the same
/// [FileRepository] the file manager itself uses (`writeFile`/
/// `readFile`), never a second content-fetching path.
///
/// Scoped by [FileEditorTarget] (`.family`), `autoDispose`: closing the
/// editor screen (back, or after a successful save) discards this
/// controller — there is nothing to keep alive once no editor is
/// showing this file (unlike the file manager listing, nothing here is
/// worth surviving a screen change).
class FileEditorController extends Notifier<FileEditorState> {
  FileEditorController(this.target);

  final FileEditorTarget target;

  FileRepository get _repository =>
      ref.read(fileRepositoryProvider((instanceId: target.instanceId, serverIdentifier: target.serverIdentifier)));

  @override
  FileEditorState build() {
    unawaited(_load());
    return FileEditorState.initial;
  }

  Future<void> _load() async {
    try {
      final content = await _repository.readFile(target.path);
      if (!ref.mounted) return;
      state = state.copyWith(
        loadStatus: FileEditorLoadStatus.loaded,
        originalContent: content,
        currentContent: content,
        clearLoadError: true,
      );
    } catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(loadStatus: FileEditorLoadStatus.error, loadError: _asAppException(error));
    }
  }

  /// Retries a failed load — the file manager's own retry pattern
  /// (`ErrorView`'s `onRetry`), nothing bespoke.
  Future<void> retryLoad() async {
    state = state.copyWith(loadStatus: FileEditorLoadStatus.loading, clearLoadError: true);
    await _load();
  }

  void updateContent(String content) {
    if (state.loadStatus != FileEditorLoadStatus.loaded) return;
    state = state.copyWith(currentContent: content, saveStatus: FileEditorSaveStatus.idle, clearSaveError: true);
  }

  /// Reverts [FileEditorState.currentContent] back to
  /// [FileEditorState.originalContent] — discards local edits without
  /// touching the server.
  void discardChanges() {
    final original = state.originalContent;
    if (original == null) return;
    state = state.copyWith(currentContent: original, saveStatus: FileEditorSaveStatus.idle, clearSaveError: true);
  }

  /// Saves [FileEditorState.currentContent]. Returns whether it
  /// succeeded, so the UI can decide what to do next (e.g. pop the
  /// screen) without re-reading [state] immediately after an `await`.
  Future<bool> save() async {
    final content = state.currentContent;
    if (content == null || state.loadStatus != FileEditorLoadStatus.loaded) return false;

    state = state.copyWith(saveStatus: FileEditorSaveStatus.saving, clearSaveError: true);
    try {
      await _repository.writeFile(target.path, content);
      if (!ref.mounted) return false;
      // The just-saved content becomes the new baseline — `isDirty` goes
      // false immediately, without a redundant re-read of the file we
      // just wrote ourselves.
      state = state.copyWith(originalContent: content, saveStatus: FileEditorSaveStatus.saved);
      return true;
    } catch (error) {
      if (!ref.mounted) return false;
      state = state.copyWith(saveStatus: FileEditorSaveStatus.error, saveError: _asAppException(error));
      return false;
    }
  }

  AppException _asAppException(Object error) => error is AppException ? error : UnknownException(cause: error);
}

final fileEditorControllerProvider =
    NotifierProvider.autoDispose.family<FileEditorController, FileEditorState, FileEditorTarget>(
  FileEditorController.new,
);
