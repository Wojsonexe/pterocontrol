import 'package:flutter/material.dart';

/// Semantic status colors — success/pending/danger/info/neutral — as a
/// [ThemeExtension], reachable through the same `Theme.of(context)` as
/// every other color instead of a brightness-blind global.
///
/// Five roles, deliberately distinct from the brand [ColorScheme.primary]:
/// a status must never be confusable with "this is a tappable action" or
/// vice-versa. [info] exists as its own role — separate from [success] —
/// specifically so "data is live/syncing" (a *process*, `SyncStatusIndicator`)
/// reads differently at a glance from "this server is running" (a
/// *state*, `ServerStatusChip`/`PowerStateChip`); conflating the two was a
/// real mistake in the previous palette (both used green).
///
/// Each role follows the on/container pattern Material 3 uses for
/// `error`/`onError`/`errorContainer`/`onErrorContainer`: the base color
/// sits *on* a surface (icon/text/dot), `onX` is text/icon color *on top
/// of* an `xContainer` fill.
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.pending,
    required this.onPending,
    required this.pendingContainer,
    required this.onPendingContainer,
    required this.danger,
    required this.onDanger,
    required this.dangerContainer,
    required this.onDangerContainer,
    required this.info,
    required this.onInfo,
    required this.infoContainer,
    required this.onInfoContainer,
    required this.neutral,
    required this.onNeutral,
    required this.neutralContainer,
    required this.onNeutralContainer,
  });

  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;

  final Color pending;
  final Color onPending;
  final Color pendingContainer;
  final Color onPendingContainer;

  final Color danger;
  final Color onDanger;
  final Color dangerContainer;
  final Color onDangerContainer;

  final Color info;
  final Color onInfo;
  final Color infoContainer;
  final Color onInfoContainer;

  final Color neutral;
  final Color onNeutral;
  final Color neutralContainer;
  final Color onNeutralContainer;

  /// Light preset — emerald/amber/rose/cyan/slate, each tuned for
  /// AA-contrast text-on-container use, not lifted from a generated tonal
  /// ramp.
  static const light = AppSemanticColors(
    success: Color(0xFF15803D),
    onSuccess: Color(0xFFFFFFFF),
    successContainer: Color(0xFFDCFCE7),
    onSuccessContainer: Color(0xFF14532D),
    pending: Color(0xFFB45309),
    onPending: Color(0xFFFFFFFF),
    pendingContainer: Color(0xFFFEF3C7),
    onPendingContainer: Color(0xFF78350F),
    danger: Color(0xFFDC2626),
    onDanger: Color(0xFFFFFFFF),
    dangerContainer: Color(0xFFFEE2E2),
    onDangerContainer: Color(0xFF7F1D1D),
    info: Color(0xFF0E7490),
    onInfo: Color(0xFFFFFFFF),
    infoContainer: Color(0xFFCFFAFE),
    onInfoContainer: Color(0xFF164E63),
    neutral: Color(0xFF64748B),
    onNeutral: Color(0xFFFFFFFF),
    neutralContainer: Color(0xFFE7E9F0),
    onNeutralContainer: Color(0xFF334155),
  );

  /// Dark preset — same hues lifted to a ~70-80 tone so they sit correctly
  /// on dark surfaces, containers deepened rather than naively inverted.
  static const dark = AppSemanticColors(
    success: Color(0xFF4ADE80),
    onSuccess: Color(0xFF0A3016),
    successContainer: Color(0xFF14432A),
    onSuccessContainer: Color(0xFFB6F5CB),
    pending: Color(0xFFFBBF24),
    onPending: Color(0xFF3F2900),
    pendingContainer: Color(0xFF4D3800),
    onPendingContainer: Color(0xFFFDE7A8),
    danger: Color(0xFFF87171),
    onDanger: Color(0xFF450A0A),
    dangerContainer: Color(0xFF5C1A1A),
    onDangerContainer: Color(0xFFFECACA),
    info: Color(0xFF22D3EE),
    onInfo: Color(0xFF042F36),
    infoContainer: Color(0xFF0E3A42),
    onInfoContainer: Color(0xFFA5F3FC),
    neutral: Color(0xFF9CA3B5),
    onNeutral: Color(0xFF20242E),
    neutralContainer: Color(0xFF2A2F3B),
    onNeutralContainer: Color(0xFFD3D7E2),
  );

  /// Convenience accessor. The `!` deliberately throws if [AppTheme]
  /// didn't register this extension — that would be a theme setup bug,
  /// not a recoverable runtime state worth a null-check.
  static AppSemanticColors of(BuildContext context) {
    return Theme.of(context).extension<AppSemanticColors>()!;
  }

  @override
  AppSemanticColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? pending,
    Color? onPending,
    Color? pendingContainer,
    Color? onPendingContainer,
    Color? danger,
    Color? onDanger,
    Color? dangerContainer,
    Color? onDangerContainer,
    Color? info,
    Color? onInfo,
    Color? infoContainer,
    Color? onInfoContainer,
    Color? neutral,
    Color? onNeutral,
    Color? neutralContainer,
    Color? onNeutralContainer,
  }) {
    return AppSemanticColors(
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      pending: pending ?? this.pending,
      onPending: onPending ?? this.onPending,
      pendingContainer: pendingContainer ?? this.pendingContainer,
      onPendingContainer: onPendingContainer ?? this.onPendingContainer,
      danger: danger ?? this.danger,
      onDanger: onDanger ?? this.onDanger,
      dangerContainer: dangerContainer ?? this.dangerContainer,
      onDangerContainer: onDangerContainer ?? this.onDangerContainer,
      info: info ?? this.info,
      onInfo: onInfo ?? this.onInfo,
      infoContainer: infoContainer ?? this.infoContainer,
      onInfoContainer: onInfoContainer ?? this.onInfoContainer,
      neutral: neutral ?? this.neutral,
      onNeutral: onNeutral ?? this.onNeutral,
      neutralContainer: neutralContainer ?? this.neutralContainer,
      onNeutralContainer: onNeutralContainer ?? this.onNeutralContainer,
    );
  }

  @override
  AppSemanticColors lerp(ThemeExtension<AppSemanticColors>? other, double t) {
    if (other is! AppSemanticColors) return this;
    return AppSemanticColors(
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      successContainer: Color.lerp(successContainer, other.successContainer, t)!,
      onSuccessContainer: Color.lerp(onSuccessContainer, other.onSuccessContainer, t)!,
      pending: Color.lerp(pending, other.pending, t)!,
      onPending: Color.lerp(onPending, other.onPending, t)!,
      pendingContainer: Color.lerp(pendingContainer, other.pendingContainer, t)!,
      onPendingContainer: Color.lerp(onPendingContainer, other.onPendingContainer, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      onDanger: Color.lerp(onDanger, other.onDanger, t)!,
      dangerContainer: Color.lerp(dangerContainer, other.dangerContainer, t)!,
      onDangerContainer: Color.lerp(onDangerContainer, other.onDangerContainer, t)!,
      info: Color.lerp(info, other.info, t)!,
      onInfo: Color.lerp(onInfo, other.onInfo, t)!,
      infoContainer: Color.lerp(infoContainer, other.infoContainer, t)!,
      onInfoContainer: Color.lerp(onInfoContainer, other.onInfoContainer, t)!,
      neutral: Color.lerp(neutral, other.neutral, t)!,
      onNeutral: Color.lerp(onNeutral, other.onNeutral, t)!,
      neutralContainer: Color.lerp(neutralContainer, other.neutralContainer, t)!,
      onNeutralContainer: Color.lerp(onNeutralContainer, other.onNeutralContainer, t)!,
    );
  }
}
