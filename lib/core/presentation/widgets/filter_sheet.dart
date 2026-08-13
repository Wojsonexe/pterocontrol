import 'package:flutter/material.dart';

import '../../theme/app_spacing.dart';
import '../../theme/app_surface_colors.dart';

@immutable
class FilterOption<T> {
  const FilterOption({required this.value, required this.label, this.icon});

  final T value;
  final String label;
  final IconData? icon;
}

/// Opens the app's standard single-select filter/sort sheet — one
/// reusable bottom sheet for "pick one of these options" (server status
/// filter, sort mode, ...) instead of each screen hand-rolling its own
/// [PopupMenuButton] with a different look. Returns the newly selected
/// value, or `null` if dismissed without a change.
Future<T?> showFilterSheet<T>({
  required BuildContext context,
  required String title,
  required List<FilterOption<T>> options,
  required T selected,
}) {
  return showModalBottomSheet<T>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      final surfaces = AppSurfaceColors.of(context);
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.xs, AppSpacing.lg, AppSpacing.sm),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
              ),
              for (final option in options)
                ListTile(
                  leading: option.icon != null ? Icon(option.icon) : null,
                  title: Text(option.label),
                  trailing: option.value == selected
                      ? Icon(Icons.check_rounded, color: theme.colorScheme.primary)
                      : null,
                  selected: option.value == selected,
                  selectedTileColor: surfaces.surfaceActive,
                  onTap: () => Navigator.of(context).pop(option.value),
                ),
            ],
          ),
        ),
      );
    },
  );
}
