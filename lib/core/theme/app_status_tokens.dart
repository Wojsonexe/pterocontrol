import 'package:flutter/material.dart';

import 'app_semantic_colors.dart';

/// The five semantic "how is this doing" categories every status in the
/// app boils down to (instance connection, server administrative status,
/// server power state, console connection state, data-sync freshness).
/// Deliberately independent of any specific domain enum — each feature
/// maps its own status values onto one of these.
///
/// [info] is its own tone, distinct from [success]: "data is live/
/// syncing right now" (a process) and "this server is running" (a state)
/// must never share a color, or a glance at the sync indicator could be
/// misread as a server status and vice versa.
enum AppStatusTone { success, pending, danger, info, neutral }

/// The resolved colors for one [AppStatusTone], pulled from
/// [AppSemanticColors] — its own small type rather than exposing
/// [AppSemanticColors] fields directly, so a future status widget depends
/// on "give me the colors for this tone" instead of reaching into every
/// field itself.
@immutable
class AppStatusColorSet {
  const AppStatusColorSet({
    required this.color,
    required this.onColor,
    required this.container,
    required this.onContainer,
  });

  /// Foreground color — icon/text sitting directly on a surface.
  final Color color;

  /// Text/icon color to use on top of [container].
  final Color onColor;

  /// Fill color for a badge/chip background.
  final Color container;

  /// Text/icon color on top of [container].
  final Color onContainer;
}

extension AppStatusToneColors on AppStatusTone {
  /// Resolves this tone against [colors] (typically
  /// `AppSemanticColors.of(context)`).
  AppStatusColorSet resolve(AppSemanticColors colors) {
    return switch (this) {
      AppStatusTone.success => AppStatusColorSet(
        color: colors.success,
        onColor: colors.onSuccess,
        container: colors.successContainer,
        onContainer: colors.onSuccessContainer,
      ),
      AppStatusTone.pending => AppStatusColorSet(
        color: colors.pending,
        onColor: colors.onPending,
        container: colors.pendingContainer,
        onContainer: colors.onPendingContainer,
      ),
      AppStatusTone.danger => AppStatusColorSet(
        color: colors.danger,
        onColor: colors.onDanger,
        container: colors.dangerContainer,
        onContainer: colors.onDangerContainer,
      ),
      AppStatusTone.info => AppStatusColorSet(
        color: colors.info,
        onColor: colors.onInfo,
        container: colors.infoContainer,
        onContainer: colors.onInfoContainer,
      ),
      AppStatusTone.neutral => AppStatusColorSet(
        color: colors.neutral,
        onColor: colors.onNeutral,
        container: colors.neutralContainer,
        onContainer: colors.onNeutralContainer,
      ),
    };
  }
}

/// What a future shared status widget (not built in this step) will need
/// to render one status value: an icon, its label, which semantic
/// [AppStatusTone] it belongs to, and whether it represents an
/// in-progress process that should animate (e.g. a spinner instead of a
/// static icon) — see design-system notes, Status section, for the full
/// per-domain mapping this will eventually replace across
/// `ConnectionStatusChip`/`ServerStatusChip`/console's status indicator.
///
/// Pure data — no widget, no `BuildContext` — so each feature's future
/// mapping function (e.g. `ServerAdministrativeStatus -> AppStatusVisual`)
/// stays trivially unit-testable.
@immutable
class AppStatusVisual {
  const AppStatusVisual({
    required this.icon,
    required this.label,
    required this.tone,
    this.isAnimated = false,
  });

  final IconData icon;
  final String label;
  final AppStatusTone tone;

  /// `true` for states representing an active, in-progress process
  /// (installing, checking, reconnecting, ...) that a future widget
  /// should render with a spinner instead of a static icon.
  final bool isAnimated;

  @override
  bool operator ==(Object other) {
    return other is AppStatusVisual &&
        other.icon == icon &&
        other.label == label &&
        other.tone == tone &&
        other.isAnimated == isAnimated;
  }

  @override
  int get hashCode => Object.hash(icon, label, tone, isAnimated);

  @override
  String toString() =>
      'AppStatusVisual(label: $label, tone: $tone, isAnimated: $isAnimated)';
}
