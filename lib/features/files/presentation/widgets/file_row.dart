import 'package:flutter/material.dart';

import '../../../../core/formatting/metric_formatting.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_semantic_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_surface_colors.dart';
import '../../application/file_manager_state.dart';
import '../../domain/file_entry.dart';

/// One row in the file manager's list — an icon by kind, name, and a
/// compact size/modified-date line, matching the identity-row shape
/// `ServerCard` already established (mark, name, secondary line) so the
/// File Manager reads as the same product, not a bolted-on module.
class FileRow extends StatelessWidget {
  const FileRow({
    super.key,
    required this.entry,
    required this.selected,
    required this.isSelecting,
    required this.busy,
    required this.onTap,
    required this.onLongPress,
    required this.onMoreTap,
  });

  final FileEntry entry;
  final bool selected;
  final bool isSelecting;
  final FileOperationKind? busy;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onMoreTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaces = AppSurfaceColors.of(context);
    final semantic = AppSemanticColors.of(context);

    final (icon, iconColor) = _iconFor(entry, semantic);

    return Material(
      color: selected ? surfaces.surfaceActive : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
          child: Row(
            children: [
              if (isSelecting)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: Icon(
                    selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                    color: selected ? theme.colorScheme.primary : surfaces.textTertiary,
                  ),
                ),
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
                child: busy != null
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: iconColor),
                      )
                    : Icon(icon, size: 18, color: iconColor),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      entry.name,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: entry.isDotfile ? surfaces.textSecondary : surfaces.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      busy != null ? _busyLabel(busy!) : _subtitleFor(entry),
                      style: theme.textTheme.labelSmall?.copyWith(color: surfaces.textTertiary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (!isSelecting)
                IconButton(
                  icon: const Icon(Icons.more_vert_rounded),
                  color: surfaces.textTertiary,
                  onPressed: onMoreTap,
                  tooltip: 'Więcej',
                ),
            ],
          ),
        ),
      ),
    );
  }

  (IconData, Color) _iconFor(FileEntry entry, AppSemanticColors semantic) {
    if (entry.isDirectory) return (Icons.folder_rounded, semantic.info);
    if (entry.isSymlink) return (Icons.link_rounded, semantic.neutral);
    if (_isArchive(entry.name)) return (Icons.folder_zip_rounded, semantic.pending);
    if (entry.isEditable) return (Icons.description_rounded, semantic.neutral);
    return (Icons.insert_drive_file_rounded, semantic.neutral);
  }

  bool _isArchive(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.tar.gz') ||
        lower.endsWith('.zip') ||
        lower.endsWith('.tar') ||
        lower.endsWith('.rar') ||
        lower.endsWith('.7z');
  }

  String _subtitleFor(FileEntry entry) {
    final modified = formatRelativeTime(entry.modifiedAt);
    if (entry.isDirectory) return modified;
    return '${formatFileSize(entry.size)} • $modified';
  }

  String _busyLabel(FileOperationKind kind) => switch (kind) {
        FileOperationKind.deleting => 'Usuwanie…',
        FileOperationKind.renaming => 'Zmiana nazwy…',
        FileOperationKind.moving => 'Przenoszenie…',
        FileOperationKind.copying => 'Kopiowanie…',
        FileOperationKind.compressing => 'Kompresowanie…',
        FileOperationKind.decompressing => 'Rozpakowywanie…',
      };
}
