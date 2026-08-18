import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/presentation/widgets/app_top_bar.dart';
import '../../../../core/presentation/widgets/error_view.dart';
import '../../../../core/theme/app_semantic_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_surface_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../application/file_editor_controller.dart';
import '../../application/file_editor_state.dart';

/// Built-in plain-text editor for one file — line numbers, search/
/// replace, save/discard, all through [FileEditorController]. Pushed
/// on top of `ServerDetailScreen` (a real navigation, not a tab — a
/// second, deeper screen, matching how opening a specific file works in
/// every reference file manager).
class FileEditorScreen extends ConsumerStatefulWidget {
  const FileEditorScreen({super.key, required this.target});

  final FileEditorTarget target;

  @override
  ConsumerState<FileEditorScreen> createState() => _FileEditorScreenState();
}

class _FileEditorScreenState extends ConsumerState<FileEditorScreen> {
  final _textController = TextEditingController();
  final _searchController = TextEditingController();
  bool _showSearch = false;
  String? _lastAppliedContent;

  @override
  void dispose() {
    _textController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _syncControllerFromState(FileEditorState state) {
    // Only overwrite the text field when the *state's* content changed
    // from underneath us (initial load, discard, a completed save) —
    // never on every rebuild, which would fight the user's own typing
    // and reset their cursor position on each keystroke.
    final content = state.currentContent;
    if (content != null && content != _lastAppliedContent && content != _textController.text) {
      _textController.value = TextEditingValue(text: content, selection: TextSelection.collapsed(offset: content.length));
      _lastAppliedContent = content;
    }
  }

  Future<bool> _confirmDiscardIfDirty(FileEditorState state) async {
    if (!state.isDirty) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Odrzucić niezapisane zmiany?'),
        content: const Text('Plik zawiera niezapisane zmiany, które zostaną utracone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Anuluj')),
          FilledButton.tonal(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Odrzuć zmiany'),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  void _findNext() {
    final query = _searchController.text;
    if (query.isEmpty) return;
    final text = _textController.text;
    final currentEnd = _textController.selection.end;
    var index = text.indexOf(query, currentEnd);
    index = index == -1 ? text.indexOf(query) : index;
    if (index == -1) return;
    _textController.selection = TextSelection(baseOffset: index, extentOffset: index + query.length);
  }

  void _replaceAll(FileEditorController notifier) {
    final query = _searchController.text;
    if (query.isEmpty) return;
    final replacement = _replaceController.text;
    final updated = _textController.text.replaceAll(query, replacement);
    _textController.text = updated;
    notifier.updateContent(updated);
  }

  final _replaceController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(fileEditorControllerProvider(widget.target));
    final notifier = ref.read(fileEditorControllerProvider(widget.target).notifier);
    final semantic = AppSemanticColors.of(context);
    final fileName = widget.target.path.split('/').last;

    if (state.loadStatus == FileEditorLoadStatus.loaded) {
      _syncControllerFromState(state);
    }

    return PopScope(
      canPop: !state.isDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscardIfDirty(state) && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppTopBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () async {
              if (await _confirmDiscardIfDirty(state) && context.mounted) Navigator.of(context).pop();
            },
          ),
          title: fileName,
          subtitle: widget.target.path,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.search_rounded),
                tooltip: 'Szukaj',
                onPressed: state.loadStatus == FileEditorLoadStatus.loaded
                    ? () => setState(() => _showSearch = !_showSearch)
                    : null,
              ),
              _SaveButton(state: state, onSave: () => notifier.save()),
            ],
          ),
        ),
        body: switch (state.loadStatus) {
          FileEditorLoadStatus.loading => const Center(child: CircularProgressIndicator()),
          FileEditorLoadStatus.error => ErrorView(
              message: state.loadError?.message ?? 'Nie udało się wczytać pliku.',
              onRetry: notifier.retryLoad,
            ),
          FileEditorLoadStatus.loaded => Column(
              children: [
                if (_showSearch) _SearchReplaceBar(searchController: _searchController, replaceController: _replaceController, onFindNext: _findNext, onReplaceAll: () => _replaceAll(notifier)),
                if (state.saveStatus == FileEditorSaveStatus.error)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                    color: semantic.dangerContainer,
                    child: Text(
                      state.saveError?.message ?? 'Nie udało się zapisać pliku.',
                      style: TextStyle(color: semantic.onDangerContainer),
                    ),
                  ),
                Expanded(child: _Editor(controller: _textController, onChanged: notifier.updateContent)),
              ],
            ),
        },
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.state, required this.onSave});

  final FileEditorState state;
  final Future<bool> Function() onSave;

  @override
  Widget build(BuildContext context) {
    if (state.saveStatus == FileEditorSaveStatus.saving) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.sm),
        child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return IconButton(
      icon: const Icon(Icons.save_rounded),
      tooltip: 'Zapisz',
      onPressed: state.isDirty ? onSave : null,
    );
  }
}

class _SearchReplaceBar extends StatelessWidget {
  const _SearchReplaceBar({
    required this.searchController,
    required this.replaceController,
    required this.onFindNext,
    required this.onReplaceAll,
  });

  final TextEditingController searchController;
  final TextEditingController replaceController;
  final VoidCallback onFindNext;
  final VoidCallback onReplaceAll;

  @override
  Widget build(BuildContext context) {
    final surfaces = AppSurfaceColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(color: surfaces.surfaceElevated, border: Border(bottom: BorderSide(color: surfaces.border))),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: searchController,
              decoration: const InputDecoration(isDense: true, hintText: 'Szukaj…'),
              onSubmitted: (_) => onFindNext(),
            ),
          ),
          IconButton(icon: const Icon(Icons.arrow_downward_rounded), onPressed: onFindNext, tooltip: 'Następne'),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: TextField(
              controller: replaceController,
              decoration: const InputDecoration(isDense: true, hintText: 'Zamień na…'),
            ),
          ),
          TextButton(onPressed: onReplaceAll, child: const Text('Zamień wszystko')),
        ],
      ),
    );
  }
}

/// Line numbers + text, scrolling together as one block — the gutter is
/// just a parallel `Text` with the exact same monospace/line-height as
/// the editable field, both inside one shared [SingleChildScrollView], so
/// they can never drift out of sync the way two independently-scrolled
/// widgets could.
class _Editor extends StatelessWidget {
  const _Editor({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final consoleColors = AppSurfaceColors.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final lineCount = '\n'.allMatches(controller.text).length + 1;
        return SingleChildScrollView(
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.only(left: AppSpacing.sm, right: AppSpacing.xs, top: 12),
                  alignment: Alignment.topRight,
                  child: Text(
                    List.generate(lineCount, (i) => '${i + 1}').join('\n'),
                    style: AppTypography.terminal.copyWith(color: consoleColors.textTertiary),
                    textAlign: TextAlign.right,
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: TextField(
                      controller: controller,
                      onChanged: onChanged,
                      maxLines: null,
                      expands: false,
                      style: AppTypography.terminal.copyWith(color: consoleColors.textPrimary),
                      decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.only(top: 12)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
