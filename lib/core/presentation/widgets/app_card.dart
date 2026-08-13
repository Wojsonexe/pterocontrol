import 'package:flutter/material.dart';

import '../../theme/app_radius.dart';
import '../../theme/app_surface_colors.dart';

/// The base surface every card-like element in the app builds on
/// (`ServerCard`, instance tiles, dashboard sections, metric cards) — one
/// implementation of "what a card looks like and how it responds to a
/// tap" instead of every screen re-deriving `Card`+`InkWell`+padding on
/// its own with slightly different values each time.
///
/// Deliberately borderless: the card reads against
/// [AppSurfaceColors.background] through tonal contrast (`surface`/
/// `surfaceElevated`), not an outline — see `AppTheme`'s doc comment for
/// why a border-per-card was the previous UI's biggest "random rectangles"
/// problem. [accent] paints a thin colored bar down the leading edge for
/// cards that need one glanceable signal even before reading any text
/// (e.g. a server's status) — omitted, most cards have none.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.padding = const EdgeInsets.all(16),
    this.elevated = false,
    this.accent,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry padding;

  /// Use [AppSurfaceColors.surfaceElevated] instead of `.surface` — for a
  /// card that needs to read as sitting above the rest of the screen (a
  /// hero/summary card), not just one more row in a list.
  final bool elevated;

  /// Optional 3px accent bar on the leading edge, in a status/brand color.
  final Color? accent;

  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final surfaces = AppSurfaceColors.of(context);
    final radius = BorderRadius.circular(AppRadius.md);

    Widget content = Padding(padding: padding, child: child);
    if (accent != null) {
      // `IntrinsicHeight`, not a bare `CrossAxisAlignment.stretch` Row: this
      // card's height comes from its content (it sits in a `ListView`/
      // `Column` that gives it unbounded height to size itself), and
      // `stretch` alone demands a *bounded* incoming height to stretch
      // children against — inside an unbounded parent that throws a
      // "BoxConstraints forces an infinite height" layout error.
      // `IntrinsicHeight` measures the content's natural height first and
      // hands the accent bar a real, finite height to stretch to.
      content = IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 3,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(AppRadius.md)),
              ),
            ),
            Expanded(child: content),
          ],
        ),
      );
    }

    final card = Material(
      color: elevated ? surfaces.surfaceElevated : surfaces.surface,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: onTap == null && onLongPress == null
          ? content
          : InkWell(onTap: onTap, onLongPress: onLongPress, child: content),
    );

    if (semanticLabel == null) return card;
    return Semantics(
      button: onTap != null,
      label: semanticLabel,
      excludeSemantics: true,
      child: card,
    );
  }
}
