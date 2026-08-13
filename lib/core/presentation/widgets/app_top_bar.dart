import 'package:flutter/material.dart';

import '../../theme/app_spacing.dart';
import '../../theme/app_surface_colors.dart';

/// The app's standard screen header — title, optional one-line subtitle
/// (a live status/count that belongs *with* the title, not competing with
/// it as a separate row of body text), and a trailing slot for small
/// indicators/actions.
///
/// A drop-in [PreferredSizeWidget] for `Scaffold.appBar`, built on plain
/// `Container`+`Row` rather than [AppBar] — [AppBar] bakes in a single
/// centered title line and fights back when asked for a title+subtitle
/// stack with custom vertical rhythm. `Scaffold` only requires its
/// `appBar` to report a height and paint itself; it does not require an
/// actual [AppBar].
class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  const AppTopBar({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.bottom,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;

  /// Small indicators/actions at the end of the title row (a status pill,
  /// an icon button) — kept to at most one or two glanceable elements;
  /// this is a header, not a toolbar.
  final Widget? trailing;

  /// Extra content below the title row (a search field, filter chips) —
  /// extends [preferredSize] to fit.
  final PreferredSizeWidget? bottom;

  @override
  Size get preferredSize => Size.fromHeight(64 + (subtitle != null ? 18 : 0) + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaces = AppSurfaceColors.of(context);

    return Material(
      color: surfaces.background,
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xs),
              child: Row(
                children: [
                  if (leading != null) ...[leading!, const SizedBox(width: AppSpacing.xs)],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.headlineSmall?.copyWith(color: surfaces.textPrimary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (subtitle case final subtitle?)
                          Text(
                            subtitle,
                            style: theme.textTheme.bodySmall?.copyWith(color: surfaces.textSecondary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  if (trailing != null) const SizedBox(width: AppSpacing.sm),
                  ?trailing,
                ],
              ),
            ),
            ?bottom,
          ],
        ),
      ),
    );
  }
}
