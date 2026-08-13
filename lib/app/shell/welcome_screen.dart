import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/presentation/widgets/fade_slide_in.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_surface_colors.dart';
import '../router/app_routes.dart';

/// First thing a brand-new user sees — shown by [RootScreen] whenever no
/// panel has ever been configured on this device, *before* the "Connect
/// panel" wizard, not instead of it. A returning user with an active
/// instance never sees this again (`RootScreen` redirects straight past
/// it); a user who once had a panel and removed the last one sees
/// [InstancesScreen]'s own picker/empty state, not this — this screen is
/// specifically "you have never set anything up yet", the one moment the
/// app should introduce itself before asking for a URL and an API key.
///
/// No account system exists (and none is invented here) — the single
/// action is "Connect your panel", which pushes [AppRoutes.addInstance]
/// directly.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaces = AppSurfaceColors.of(context);

    return Scaffold(
      backgroundColor: surfaces.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.xl, AppSpacing.lg, AppSpacing.lg),
          child: Column(
            children: [
              const Spacer(flex: 2),
              FadeSlideIn(
                child: Container(
                  width: 72,
                  height: 72,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    boxShadow: [
                      BoxShadow(color: theme.colorScheme.primary.withValues(alpha: 0.28), blurRadius: 32, spreadRadius: -6),
                    ],
                  ),
                  child: Icon(Icons.hub_rounded, size: 36, color: theme.colorScheme.onPrimary),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              FadeSlideIn(
                child: Text(
                  'Twoje serwery.\nZawsze pod ręką.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.displaySmall?.copyWith(color: surfaces.textPrimary, height: 1.15),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              FadeSlideIn(
                child: Text(
                  'Podłącz swój panel Pterodactyl i zarządzaj wszystkimi '
                  'serwerami z jednego miejsca — status, zużycie zasobów '
                  'i konsola, na żywo.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(color: surfaces.textSecondary),
                ),
              ),
              const Spacer(flex: 2),
              FadeSlideIn(
                child: Column(
                  children: [
                    _Highlight(icon: Icons.bolt_rounded, label: 'Status i zasoby w czasie rzeczywistym'),
                    const SizedBox(height: AppSpacing.sm),
                    _Highlight(icon: Icons.terminal_rounded, label: 'Konsola i sterowanie serwerem'),
                    const SizedBox(height: AppSpacing.sm),
                    _Highlight(icon: Icons.dns_rounded, label: 'Wiele paneli, jedna aplikacja'),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => context.push(AppRoutes.addInstance),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.xxs),
                    child: Text('Połącz panel'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Highlight extends StatelessWidget {
  const _Highlight({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaces = AppSurfaceColors.of(context);

    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(AppRadius.xs),
          ),
          child: Icon(icon, size: 17, color: theme.colorScheme.primary),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: surfaces.textSecondary)),
        ),
      ],
    );
  }
}
