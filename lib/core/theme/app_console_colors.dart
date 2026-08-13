import 'package:flutter/material.dart';

/// Palette for the console/terminal panel — deliberately its own
/// [ThemeExtension], separate from [AppSemanticColors]/[ColorScheme].
///
/// The terminal is intentionally *always dark*, regardless of the app's
/// light/dark theme (matching every real terminal/console UI) — mixing
/// its colors into the normal `ColorScheme` would be wrong, since e.g.
/// `colorScheme.surface` must keep meaning "the app's current surface,"
/// light or dark, while the console's background must never change with
/// it. Registering this as its own extension (with the *same* values in
/// both `AppTheme.light()` and `AppTheme.dark()`) keeps `ThemeData` the
/// single source of truth for this palette too, without conflating the
/// two concerns.
///
/// Not consumed anywhere yet — `ConsoleView` still hard-codes these same
/// literal values inline. This type exists so a future migration (see
/// design-system notes, Console stage) has one place to switch to
/// instead of repeating the hex codes a second time.
@immutable
class AppConsoleColors extends ThemeExtension<AppConsoleColors> {
  const AppConsoleColors({
    required this.background,
    required this.mutedText,
    required this.outputText,
    required this.daemonMessageText,
    required this.daemonErrorText,
  });

  final Color background;
  final Color mutedText;
  final Color outputText;
  final Color daemonMessageText;
  final Color daemonErrorText;

  /// Matches the literal values `ConsoleView` hard-codes today exactly —
  /// intentional, so plugging this in later is a pure refactor with zero
  /// visual change, not a redesign bundled into a rename.
  static const value = AppConsoleColors(
    background: Color(0xFF0D1117),
    mutedText: Color(0xFF8B949E),
    outputText: Color(0xFFC9D1D9),
    daemonMessageText: Color(0xFF58A6FF),
    daemonErrorText: Color(0xFFFF7B72),
  );

  static AppConsoleColors of(BuildContext context) {
    return Theme.of(context).extension<AppConsoleColors>()!;
  }

  @override
  AppConsoleColors copyWith({
    Color? background,
    Color? mutedText,
    Color? outputText,
    Color? daemonMessageText,
    Color? daemonErrorText,
  }) {
    return AppConsoleColors(
      background: background ?? this.background,
      mutedText: mutedText ?? this.mutedText,
      outputText: outputText ?? this.outputText,
      daemonMessageText: daemonMessageText ?? this.daemonMessageText,
      daemonErrorText: daemonErrorText ?? this.daemonErrorText,
    );
  }

  @override
  AppConsoleColors lerp(ThemeExtension<AppConsoleColors>? other, double t) {
    if (other is! AppConsoleColors) return this;
    return AppConsoleColors(
      background: Color.lerp(background, other.background, t)!,
      mutedText: Color.lerp(mutedText, other.mutedText, t)!,
      outputText: Color.lerp(outputText, other.outputText, t)!,
      daemonMessageText: Color.lerp(
        daemonMessageText,
        other.daemonMessageText,
        t,
      )!,
      daemonErrorText: Color.lerp(daemonErrorText, other.daemonErrorText, t)!,
    );
  }
}
