import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../core/presentation/widgets/empty_state_view.dart';
import '../../../../core/presentation/widgets/error_view.dart';
import '../../../../core/presentation/widgets/skeleton_box.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_semantic_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_surface_colors.dart';
import '../../application/file_manager_controller.dart';
import '../../application/file_manager_state.dart';
import '../../domain/file_entry.dart';
import '../../domain/file_target.dart';
import '../widgets/file_row.dart';
import '../widgets/file_transfer_bar.dart';
import 'file_editor_screen.dart';

/// Full file manager for one server — list/navigate/create/rename/move/
/// copy/delete/compress/decompress/upload/download, all through
/// [FileManagerController]. Embedded directly as `ServerDetailScreen`'s
/// "Pliki" tab content (a plain widget, not its own `Scaffold`/`AppBar`
/// — it shares that screen's single top bar, the same way every other
/// tab does).
class FileManagerScreen extends ConsumerWidget {
  const FileManagerScreen({super.key, required this.instanceId, required this.serverIdentifier});

  final String instanceId;
  final String serverIdentifier;

  FileTarget get _target => (instanceId: instanceId, serverIdentifier: serverIdentifier);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(fileManagerControllerProvider(_target));
    final notifier = ref.read(fileManagerControllerProvider(_target).notifier);
    final surfaces = AppSurfaceColors.of(context);

    return Column(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(color: surfaces.background, border: Border(bottom: BorderSide(color: surfaces.border))),
          child: state.isSelecting
              ? _SelectionBar(state: state, notifier: notifier, target: _target)
              : _BreadcrumbBar(state: state, notifier: notifier),
        ),
        for (final transfer in state.transfers)
          FileTransferBar(
            transfer: transfer,
            onCancel: () => notifier.cancelTransfer(transfer.id),
            onDismiss: () => notifier.dismissTransfer(transfer.id),
          ),
        Expanded(child: _Body(state: state, notifier: notifier, target: _target)),
      ],
    );
  }
}

class _BreadcrumbBar extends StatelessWidget {
  const _BreadcrumbBar({required this.state, required this.notifier});

  final FileManagerState state;
  final FileManagerController notifier;

  @override
  Widget build(BuildContext context) {
    final surfaces = AppSurfaceColors.of(context);
    final segments = state.currentPath == '/' ? const <String>[] : state.currentPath.substring(1).split('/');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
      child: Row(
        children: [
          if (state.currentPath != '/')
            IconButton(
              icon: const Icon(Icons.arrow_upward_rounded),
              tooltip: 'W górę',
              onPressed: notifier.goUp,
            ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _BreadcrumbSegment(label: '/', onTap: () => notifier.navigateTo('/'), isLast: segments.isEmpty),
                  for (var i = 0; i < segments.length; i++) ...[
                    Icon(Icons.chevron_right_rounded, size: 16, color: surfaces.textTertiary),
                    _BreadcrumbSegment(
                      label: segments[i],
                      onTap: () => notifier.navigateTo('/${segments.sublist(0, i + 1).join('/')}'),
                      isLast: i == segments.length - 1,
                    ),
                  ],
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined),
            tooltip: 'Nowy',
            onPressed: () => _showCreateSheet(context, notifier, state.currentPath),
          ),
        ],
      ),
    );
  }
}

class _BreadcrumbSegment extends StatelessWidget {
  const _BreadcrumbSegment({required this.label, required this.onTap, required this.isLast});

  final String label;
  final VoidCallback onTap;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaces = AppSurfaceColors.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.xs),
      onTap: isLast ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs, vertical: AppSpacing.xxs),
        child: Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: isLast ? surfaces.textPrimary : surfaces.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({required this.state, required this.notifier, required this.target});

  final FileManagerState state;
  final FileManagerController notifier;
  final FileTarget target;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaces = AppSurfaceColors.of(context);
    final semantic = AppSemanticColors.of(context);
    final count = state.selectedPaths.length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xxs),
      child: Row(
        children: [
          IconButton(icon: const Icon(Icons.close_rounded), onPressed: notifier.clearSelection, tooltip: 'Anuluj zaznaczenie'),
          Expanded(
            child: Text('Wybrano: $count', style: theme.textTheme.titleSmall?.copyWith(color: surfaces.textPrimary)),
          ),
          IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: 'Pobierz',
            onPressed: () => _downloadSelection(context, notifier, state, target),
          ),
          IconButton(
            icon: const Icon(Icons.drive_file_move_outlined),
            tooltip: 'Przenieś',
            onPressed: () => _showMoveSheet(context, notifier, state.selectedPaths.toList(), state.currentPath),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline_rounded, color: semantic.danger),
            tooltip: 'Usuń',
            onPressed: () => _confirmDeleteMany(context, notifier, state.selectedPaths.toList()),
          ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.state, required this.notifier, required this.target});

  final FileManagerState state;
  final FileManagerController notifier;
  final FileTarget target;

  @override
  Widget build(BuildContext context) {
    if (state.status == FileManagerLoadStatus.loading) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        children: [
          for (var i = 0; i < 6; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
              child: SkeletonBox(height: 48, borderRadius: BorderRadius.circular(AppRadius.sm)),
            ),
        ],
      );
    }

    if (state.status == FileManagerLoadStatus.error) {
      return ErrorView(
        message: state.error?.message ?? 'Nie udało się wczytać plików.',
        onRetry: notifier.refresh,
      );
    }

    if (state.entries.isEmpty) {
      return RefreshIndicator(
        onRefresh: notifier.refresh,
        child: ListView(
          children: [
            SizedBox(
              height: 320,
              child: EmptyStateView(
                icon: Icons.folder_open_rounded,
                title: 'Pusty katalog',
                message: 'Ten katalog nie zawiera jeszcze żadnych plików.',
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: notifier.refresh,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        itemCount: state.entries.length,
        itemBuilder: (context, index) {
          final entry = state.entries[index];
          return FileRow(
            entry: entry,
            selected: state.selectedPaths.contains(entry.path),
            isSelecting: state.isSelecting,
            busy: state.busyPaths[entry.path],
            onTap: () => _handleTap(context, entry, state, notifier, target),
            onLongPress: () => notifier.toggleSelection(entry.path),
            onMoreTap: () => _showEntrySheet(context, notifier, entry, state.currentPath),
          );
        },
      ),
    );
  }

  void _handleTap(
    BuildContext context,
    FileEntry entry,
    FileManagerState state,
    FileManagerController notifier,
    FileTarget target,
  ) {
    if (state.isSelecting) {
      notifier.toggleSelection(entry.path);
      return;
    }
    if (entry.isDirectory) {
      notifier.navigateTo(entry.path);
      return;
    }
    if (entry.isEditable) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => FileEditorScreen(
            target: (instanceId: target.instanceId, serverIdentifier: target.serverIdentifier, path: entry.path),
          ),
        ),
      );
      return;
    }
    _showEntrySheet(context, notifier, entry, state.currentPath);
  }
}

// --- Action sheets/dialogs -------------------------------------------

void _showCreateSheet(BuildContext context, FileManagerController notifier, String currentPath) {
  showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) {
      return SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: const Text('Nowy folder'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _promptForName(context, title: 'Nowy folder', label: 'Nazwa folderu').then((name) {
                  if (name != null && name.isNotEmpty) notifier.createFolder(name);
                });
              },
            ),
            ListTile(
              leading: const Icon(Icons.note_add_outlined),
              title: const Text('Nowy plik'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _promptForName(context, title: 'Nowy plik', label: 'Nazwa pliku').then((name) {
                  if (name != null && name.isNotEmpty) notifier.createFile(name);
                });
              },
            ),
            ListTile(
              leading: const Icon(Icons.upload_outlined),
              title: const Text('Prześlij plik'),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                final picked = await FilePicker.pickFile();
                if (picked?.path == null) return;
                notifier.startUpload(localFilePath: picked!.path!, fileName: picked.name);
              },
            ),
          ],
        ),
      );
    },
  );
}

void _showEntrySheet(BuildContext context, FileManagerController notifier, FileEntry entry, String currentPath) {
  showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) {
      return SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('Zmień nazwę'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _promptForName(context, title: 'Zmień nazwę', label: 'Nazwa', initialValue: entry.name).then((name) {
                  if (name != null && name.isNotEmpty && name != entry.name) notifier.rename(entry.path, name);
                });
              },
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_move_outlined),
              title: const Text('Przenieś'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _showMoveSheet(context, notifier, [entry.path], currentPath);
              },
            ),
            if (entry.isFile)
              ListTile(
                leading: const Icon(Icons.copy_outlined),
                title: const Text('Duplikuj'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  notifier.copyEntry(entry.path);
                },
              ),
            if (entry.isFile)
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text('Pobierz'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _downloadEntry(context, notifier, entry);
                },
              ),
            if (_isArchiveName(entry.name))
              ListTile(
                leading: const Icon(Icons.unarchive_outlined),
                title: const Text('Rozpakuj'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  notifier.decompressEntry(entry.path);
                },
              ),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: AppSemanticColors.of(sheetContext).danger),
              title: const Text('Usuń'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _confirmDeleteMany(context, notifier, [entry.path]);
              },
            ),
          ],
        ),
      );
    },
  );
}

bool _isArchiveName(String name) {
  final lower = name.toLowerCase();
  return lower.endsWith('.tar.gz') || lower.endsWith('.zip') || lower.endsWith('.tar');
}

Future<String?> _promptForName(
  BuildContext context, {
  required String title,
  required String label,
  String? initialValue,
}) {
  final controller = TextEditingController(text: initialValue);
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(labelText: label),
        onSubmitted: (value) => Navigator.of(dialogContext).pop(value.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Anuluj')),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

Future<void> _confirmDeleteMany(BuildContext context, FileManagerController notifier, List<String> paths) async {
  final danger = AppSemanticColors.of(context).danger;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(paths.length == 1 ? 'Usunąć plik?' : 'Usunąć ${paths.length} elementy?'),
      content: Text(
        paths.length == 1
            ? '"${paths.first.split('/').last}" zostanie trwale usunięty.'
            : 'Wybrane elementy zostaną trwale usunięte.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Anuluj')),
        FilledButton.tonal(
          style: FilledButton.styleFrom(foregroundColor: danger),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Usuń'),
        ),
      ],
    ),
  );
  if (confirmed ?? false) {
    await notifier.deleteEntries(paths);
    notifier.clearSelection();
  }
}

Future<void> _showMoveSheet(
  BuildContext context,
  FileManagerController notifier,
  List<String> paths,
  String currentPath,
) async {
  final destination = await _promptForName(
    context,
    title: 'Przenieś do',
    label: 'Ścieżka docelowa (np. /backup)',
    initialValue: currentPath,
  );
  if (destination == null || destination.isEmpty) return;
  final normalized = destination.startsWith('/') ? destination : '/$destination';
  await notifier.moveEntries(paths, normalized);
  notifier.clearSelection();
}

Future<void> _downloadEntry(BuildContext context, FileManagerController notifier, FileEntry entry) async {
  try {
    final dir = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
    final savePath = '${dir.path}/${entry.name}';
    notifier.startDownload(entry: entry, savePath: savePath);
  } catch (_) {
    // No accessible storage directory — the transfer simply cannot start;
    // nothing left to roll back since nothing was created.
  }
}

Future<void> _downloadSelection(
  BuildContext context,
  FileManagerController notifier,
  FileManagerState state,
  FileTarget target,
) async {
  final selected = state.entries.where((e) => state.selectedPaths.contains(e.path) && e.isFile);
  for (final entry in selected) {
    await _downloadEntry(context, notifier, entry);
  }
  notifier.clearSelection();
}
