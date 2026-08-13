import 'package:flutter/material.dart';

/// The app's own surface system — background / surface / elevated surface /
/// active (pressed-or-selected) fill / hairline border / three text
/// emphasis levels — registered as a [ThemeExtension] alongside
/// [ColorScheme] rather than reusing `colorScheme.surface`/
/// `surfaceContainerHighest`/etc. directly.
///
/// Why a second surface system instead of Material 3's own tonal
/// surfaces: M3's `ColorScheme.fromSeed` derives every surface tone from
/// one seed by formula, which is exactly why the stock look reads as
/// generic — every seeded Material app's surfaces relate to each other
/// the same way. [background]/[surface]/[surfaceElevated]/[surfaceActive]
/// here are hand-picked per brightness (see [light]/[dark]) so dark mode
/// is a deliberately designed second palette, not `background = near
/// black` with the light palette's tones inverted through a formula.
@immutable
class AppSurfaceColors extends ThemeExtension<AppSurfaceColors> {
  const AppSurfaceColors({
    required this.background,
    required this.surface,
    required this.surfaceElevated,
    required this.surfaceActive,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
  });

  /// The screen's own backdrop, behind every card/surface.
  final Color background;

  /// A resting card/sheet/tile surface — one step "up" from [background].
  final Color surface;

  /// A surface that should read as sitting visibly above [surface] (a
  /// hero card, a bottom sheet, a dialog) — a further step up, not just a
  /// shadow on the same flat color.
  final Color surfaceElevated;

  /// Fill for a pressed, selected, or otherwise "currently engaged" state
  /// (a tapped list row, the selected filter chip, the active nav pill).
  final Color surfaceActive;

  /// Hairline dividers/card outlines.
  final Color border;

  /// A more visible border — a focused input, a selected card's outline.
  final Color borderStrong;

  final Color textPrimary;
  final Color textSecondary;

  /// Placeholder/disabled/least-important text (timestamps, helper
  /// captions) — one step quieter than [textSecondary].
  final Color textTertiary;

  static const light = AppSurfaceColors(
    background: Color(0xFFF6F6F9),
    surface: Color(0xFFFFFFFF),
    surfaceElevated: Color(0xFFFFFFFF),
    surfaceActive: Color(0xFFEEF0F5),
    border: Color(0xFFE6E8EF),
    borderStrong: Color(0xFFCDD1DD),
    textPrimary: Color(0xFF13151B),
    textSecondary: Color(0xFF5B6072),
    textTertiary: Color(0xFF8B8FA0),
  );

  static const dark = AppSurfaceColors(
    background: Color(0xFF0A0C11),
    surface: Color(0xFF13161D),
    surfaceElevated: Color(0xFF1A1E27),
    surfaceActive: Color(0xFF232833),
    border: Color(0xFF262B36),
    borderStrong: Color(0xFF3A404E),
    textPrimary: Color(0xFFF3F4F8),
    textSecondary: Color(0xFFA3A8BA),
    textTertiary: Color(0xFF6E7385),
  );

  static AppSurfaceColors of(BuildContext context) {
    return Theme.of(context).extension<AppSurfaceColors>()!;
  }

  @override
  AppSurfaceColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceElevated,
    Color? surfaceActive,
    Color? border,
    Color? borderStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
  }) {
    return AppSurfaceColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      surfaceActive: surfaceActive ?? this.surfaceActive,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
    );
  }

  @override
  AppSurfaceColors lerp(ThemeExtension<AppSurfaceColors>? other, double t) {
    if (other is! AppSurfaceColors) return this;
    return AppSurfaceColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      surfaceActive: Color.lerp(surfaceActive, other.surfaceActive, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
    );
  }
}
