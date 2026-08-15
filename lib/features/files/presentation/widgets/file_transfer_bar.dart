import 'package:flutter/material.dart';

import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_semantic_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_surface_colors.dart';
import '../../application/file_transfer_task.dart';

/// One upload/download's progress, cancel button, and terminal-state
/// message — a compact card, not a full-screen blocking overlay (see the
/// task's "nie blokuj całego UI podczas uploadu").
class FileTransferBar extends StatelessWidget {
  const FileTransferBar({super.key, required this.transfer, required this.onCancel, required this.onDismiss});

  final FileTransferTask transfer;
  final VoidCallback onCancel;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaces = AppSurfaceColors.of(context);
    final semantic = AppSemanticColors.of(context);

    final icon = transfer.direction == FileTransferDirection.upload ? Icons.upload_rounded : Icons.download_rounded;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xxs),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: surfaces.surfaceElevated,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: surfaces.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: surfaces.textSecondary),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  transfer.fileName,
                  style: theme.textTheme.labelLarge?.copyWith(color: surfaces.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                if (transfer.status == FileTransferStatus.inProgress)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    child: LinearProgressIndicator(value: transfer.progress, minHeight: 4),
                  )
                else
                  Text(_statusLabel(transfer, semantic), style: theme.textTheme.labelSmall?.copyWith(color: _statusColor(transfer, semantic))),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          if (transfer.status == FileTransferStatus.inProgress)
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 18),
              tooltip: 'Anuluj',
              onPressed: onCancel,
              visualDensity: VisualDensity.compact,
            )
          else
            IconButton(
              icon: const Icon(Icons.check_rounded, size: 18),
              tooltip: 'Zamknij',
              onPressed: onDismiss,
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }

  String _statusLabel(FileTransferTask transfer, AppSemanticColors semantic) => switch (transfer.status) {
        FileTransferStatus.success =>
          transfer.direction == FileTransferDirection.upload ? 'Przesłano' : 'Pobrano',
        FileTransferStatus.failed => transfer.error?.message ?? 'Nie udało się.',
        FileTransferStatus.cancelled => 'Anulowano.',
        FileTransferStatus.inProgress => '',
      };

  Color _statusColor(FileTransferTask transfer, AppSemanticColors semantic) => switch (transfer.status) {
        FileTransferStatus.success => semantic.success,
        FileTransferStatus.failed => semantic.danger,
        FileTransferStatus.cancelled => semantic.neutral,
        FileTransferStatus.inProgress => semantic.neutral,
      };
}
