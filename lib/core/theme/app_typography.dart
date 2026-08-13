import 'package:flutter/material.dart';

/// The app's type system: **Sora** (a geometric, slightly technical
/// display face) for anything that reads as a heading/number-you-glance-at
/// — screen titles, hero stats, section headers — and **Inter** (tuned for
/// small-size legibility) for everything read as text — body copy, list
/// content, labels/buttons. Two families with a clear job split, not one
/// face doing everything (which is what made the previous, unset-family
/// scale read as a generic system default rather than a designed product).
///
/// Both are bundled as variable-font assets (`pubspec.yaml`) — offline,
/// deterministic in tests, no runtime font-fetch dependency.
///
/// Explicit [TextTheme], not left to whatever `ThemeData`'s M3 baseline
/// defaults to on a given Flutter version — a scale tuned for a phone
/// screen (M3's own baseline display sizes are print/desktop-scaled and
/// go entirely unused in this app), locked so a Flutter upgrade can't
/// silently shift it.
///
/// Design-system role → M3 slot: screen hero title → `headlineSmall` ·
/// section/card title → `titleLarge` · list item title → `titleMedium` ·
/// dense title (chip/tab) → `titleSmall` · body copy → `bodyLarge` ·
/// secondary body/list subtitle → `bodyMedium` · caption/timestamp →
/// `bodySmall` · button/action label → `labelLarge` · status badge label →
/// `labelMedium` · smallest caption (metric unit, overline) → `labelSmall`.
///
/// Colors are intentionally left unset in [_overrides] — [textTheme]
/// merges these on top of a [ColorScheme]-aware baseline, which is what
/// keeps text correctly colored in both light and dark without this file
/// knowing about brightness. Screens needing the app's own
/// [AppSurfaceColors] text emphasis levels (primary/secondary/tertiary)
/// apply those explicitly per the design system's surface roles instead.
abstract final class AppTypography {
  static const _display = 'Sora';
  static const _text = 'Inter';

  /// Builds the app's [TextTheme] for [colorScheme]'s brightness, with
  /// this file's explicit sizes/weights/families merged on top of the M3
  /// baseline (which supplies color and any slot not listed in
  /// [_overrides]).
  static TextTheme textTheme(ColorScheme colorScheme) {
    final baseline = ThemeData(colorScheme: colorScheme, useMaterial3: true).textTheme;
    return baseline.merge(_overrides);
  }

  static const _overrides = TextTheme(
    displayLarge: TextStyle(
      fontFamily: _display,
      fontSize: 40,
      height: 46 / 40,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.5,
    ),
    displayMedium: TextStyle(
      fontFamily: _display,
      fontSize: 34,
      height: 40 / 34,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.4,
    ),
    displaySmall: TextStyle(
      fontFamily: _display,
      fontSize: 28,
      height: 34 / 28,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.3,
    ),
    headlineLarge: TextStyle(
      fontFamily: _display,
      fontSize: 26,
      height: 32 / 26,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2,
    ),
    headlineMedium: TextStyle(
      fontFamily: _display,
      fontSize: 23,
      height: 29 / 23,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2,
    ),
    headlineSmall: TextStyle(
      fontFamily: _display,
      fontSize: 20,
      height: 26 / 20,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.1,
    ),
    titleLarge: TextStyle(
      fontFamily: _display,
      fontSize: 18,
      height: 24 / 18,
      fontWeight: FontWeight.w600,
    ),
    titleMedium: TextStyle(
      fontFamily: _text,
      fontSize: 15,
      height: 20 / 15,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
    ),
    titleSmall: TextStyle(
      fontFamily: _text,
      fontSize: 13,
      height: 18 / 13,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
    ),
    bodyLarge: TextStyle(
      fontFamily: _text,
      fontSize: 16,
      height: 23 / 16,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.1,
    ),
    bodyMedium: TextStyle(
      fontFamily: _text,
      fontSize: 14,
      height: 20 / 14,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.1,
    ),
    bodySmall: TextStyle(
      fontFamily: _text,
      fontSize: 12.5,
      height: 17 / 12.5,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.1,
    ),
    labelLarge: TextStyle(
      fontFamily: _text,
      fontSize: 14,
      height: 18 / 14,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
    ),
    labelMedium: TextStyle(
      fontFamily: _text,
      fontSize: 12,
      height: 16 / 12,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
    ),
    labelSmall: TextStyle(
      fontFamily: _text,
      fontSize: 11,
      height: 14 / 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.3,
    ),
  );

  /// A numeric metric value (CPU%, MB, uptime) set in [_display] with
  /// tabular figures, so digits in a column of stat cards/rows line up
  /// instead of each glyph claiming its own natural width. Callers pick
  /// their own size/weight/color and merge this in, e.g.
  /// `AppTypography.metricNumber.copyWith(fontSize: 28)`.
  static const metricNumber = TextStyle(
    fontFamily: _display,
    fontWeight: FontWeight.w600,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// Terminal/monospace text style for the console output panel — the one
  /// place in the app that intentionally does not use [_display]/[_text]
  /// (a real terminal needs a monospace face, and must look like a
  /// terminal regardless of the app's own type system).
  static const terminal = TextStyle(
    fontFamily: 'monospace',
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeight.w400,
  );
}
