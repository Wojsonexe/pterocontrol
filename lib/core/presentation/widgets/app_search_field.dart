import 'package:flutter/material.dart';

import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_surface_colors.dart';

/// The app's search field — a filled, fully-rounded pill (distinct from
/// the sharper [AppRadius.sm] used by form inputs elsewhere) so it reads
/// as "search/filter this list" at a glance rather than as a form field
/// asking for data entry.
class AppSearchField extends StatelessWidget {
  const AppSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.hintText = 'Szukaj…',
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    final surfaces = AppSurfaceColors.of(context);

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Container(
          decoration: BoxDecoration(
            color: surfaces.surfaceActive,
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            style: Theme.of(context).textTheme.bodyMedium,
            decoration: InputDecoration(
              isDense: true,
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              hintText: hintText,
              prefixIcon: Icon(Icons.search_rounded, color: surfaces.textTertiary, size: 20),
              contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              suffixIcon: controller.text.isEmpty
                  ? null
                  : IconButton(
                      icon: Icon(Icons.close_rounded, color: surfaces.textTertiary, size: 18),
                      tooltip: 'Wyczyść',
                      onPressed: () {
                        controller.clear();
                        onChanged('');
                      },
                    ),
            ),
          ),
        );
      },
    );
  }
}
