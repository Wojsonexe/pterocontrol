import 'package:flutter/material.dart';

import 'app_console_colors.dart';
import 'app_radius.dart';
import 'app_semantic_colors.dart';
import 'app_surface_colors.dart';
import 'app_typography.dart';

/// Light and dark [ThemeData] for the app — the single source of truth
/// for color, typography, and every global Material component style.
///
/// Deliberately **not** `ColorScheme.fromSeed` for the roles that define
/// the app's identity (`primary`/`surface`/`background`/borders/text) —
/// a single-seed tonal palette is exactly why a from-seed M3 app reads as
/// generic: every such app's surfaces relate to each other by the same
/// formula. [_seedColor] still seeds a baseline `ColorScheme` (used only
/// for the handful of roles this file does not override — `tertiary`,
/// `outlineVariant` fallback, `surfaceContainerHighest`, `shadow`, ...),
/// then [_build] overrides every role that actually shapes what the app
/// looks like with hand-picked values from [AppSurfaceColors]/the brand
/// indigo below.
///
/// [AppSurfaceColors]/[AppSemanticColors]/[AppConsoleColors] are
/// registered as [ThemeData.extensions] — reachable through the exact
/// same `Theme.of(context)` as every built-in color.
abstract final class AppTheme {
  static const _seedColor = Color(0xFF4A54F1);

  /// Brand indigo — primary actions, active nav state, links, the one
  /// accent color used for "this is interactive/selected", never for a
  /// status (see [AppSemanticColors] for those).
  static const _primaryLight = Color(0xFF4A54F1);
  static const _onPrimaryLight = Color(0xFFFFFFFF);
  static const _primaryContainerLight = Color(0xFFE3E4FF);
  static const _onPrimaryContainerLight = Color(0xFF1A1F6B);

  static const _primaryDark = Color(0xFFA9AEFF);
  static const _onPrimaryDark = Color(0xFF1D2178);
  static const _primaryContainerDark = Color(0xFF33379B);
  static const _onPrimaryContainerDark = Color(0xFFE3E4FF);

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final surfaces = isLight ? AppSurfaceColors.light : AppSurfaceColors.dark;
    final semanticColors = isLight ? AppSemanticColors.light : AppSemanticColors.dark;

    final baseline = ColorScheme.fromSeed(seedColor: _seedColor, brightness: brightness);
    final colorScheme = baseline.copyWith(
      primary: isLight ? _primaryLight : _primaryDark,
      onPrimary: isLight ? _onPrimaryLight : _onPrimaryDark,
      primaryContainer: isLight ? _primaryContainerLight : _primaryContainerDark,
      onPrimaryContainer: isLight ? _onPrimaryContainerLight : _onPrimaryContainerDark,
      surface: surfaces.surface,
      onSurface: surfaces.textPrimary,
      onSurfaceVariant: surfaces.textSecondary,
      surfaceContainerHighest: surfaces.surfaceActive,
      outline: surfaces.borderStrong,
      outlineVariant: surfaces.border,
      error: semanticColors.danger,
      onError: semanticColors.onDanger,
      errorContainer: semanticColors.dangerContainer,
      onErrorContainer: semanticColors.onDangerContainer,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      textTheme: AppTypography.textTheme(colorScheme),
      scaffoldBackgroundColor: surfaces.background,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      extensions: <ThemeExtension<dynamic>>[
        surfaces,
        semanticColors,
        AppConsoleColors.value,
      ],
      appBarTheme: AppBarTheme(
        backgroundColor: surfaces.background,
        foregroundColor: surfaces.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: AppTypography.textTheme(colorScheme).titleLarge?.copyWith(color: surfaces.textPrimary),
        iconTheme: IconThemeData(color: surfaces.textPrimary),
        centerTitle: false,
      ),
      // Flat, borderless surface — a card is defined by its contrast
      // against `scaffoldBackgroundColor`, not by an outline drawn around
      // it (an outline-per-card is what made the previous look read as
      // "random rectangles" — the fix is tonal depth, not a thicker line).
      cardTheme: CardThemeData(
        elevation: 0,
        color: surfaces.surface,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      ),
      dividerTheme: DividerThemeData(color: surfaces.border, thickness: 1, space: 1),
      listTileTheme: ListTileThemeData(
        iconColor: surfaces.textSecondary,
        textColor: surfaces.textPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
      ),
      // Primary. Rounded-rect (AppRadius.md), not Material 3's default
      // pill/stadium shape — buttons visually match card geometry instead
      // of the two competing for attention. minimumSize locks the 48dp
      // touch target explicitly rather than relying on default padding.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 48),
          textStyle: AppTypography.textTheme(colorScheme).labelLarge,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        ),
      ),
      // Secondary.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          textStyle: AppTypography.textTheme(colorScheme).labelLarge,
          side: BorderSide(color: surfaces.borderStrong),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        ),
      ),
      // Tertiary.
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(64, 48),
          textStyle: AppTypography.textTheme(colorScheme).labelLarge,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48), foregroundColor: surfaces.textSecondary),
      ),
      // No destructive ButtonThemeData by design — Primary/Secondary/
      // Tertiary must not default to red. Destructive styling stays a
      // per-instance override reading `AppSemanticColors.of(context).danger`.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaces.surface,
        hintStyle: TextStyle(color: surfaces.textTertiary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: surfaces.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: surfaces.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: colorScheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: colorScheme.error, width: 1.5),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: surfaces.border.withValues(alpha: 0.5)),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.label,
        labelColor: colorScheme.primary,
        unselectedLabelColor: surfaces.textSecondary,
        labelStyle: AppTypography.textTheme(colorScheme).titleSmall,
        unselectedLabelStyle: AppTypography.textTheme(colorScheme).titleSmall,
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: colorScheme.primary, width: 2.5),
          insets: const EdgeInsets.symmetric(horizontal: 4),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaces.surfaceActive,
        selectedColor: colorScheme.primaryContainer,
        labelStyle: AppTypography.textTheme(colorScheme).labelMedium?.copyWith(color: surfaces.textPrimary),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.full)),
        padding: const EdgeInsets.symmetric(horizontal: 4),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surfaces.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: surfaces.border,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaces.textPrimary,
        contentTextStyle: AppTypography.textTheme(colorScheme).bodyMedium?.copyWith(color: surfaces.background),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: colorScheme.primary),
    );
  }
}
