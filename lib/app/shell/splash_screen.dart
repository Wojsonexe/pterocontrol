import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_surface_colors.dart';

/// Branded loading frame shown for the brief moment [RootScreen] is
/// waiting on `instanceListControllerProvider` (reading the locally
/// stored panel list) — the very first thing a user ever sees when
/// opening the app, so it carries the brand mark rather than a bare,
/// unbranded spinner.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 420))..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaces = AppSurfaceColors.of(context);
    final curved = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);

    return Scaffold(
      backgroundColor: surfaces.background,
      body: Center(
        child: FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween(begin: 0.92, end: 1.0).animate(curved),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(color: theme.colorScheme.primary.withValues(alpha: 0.28), blurRadius: 28, spreadRadius: -4),
                    ],
                  ),
                  child: Icon(Icons.hub_rounded, size: 40, color: theme.colorScheme.onPrimary),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text('Pterodactyl', style: theme.textTheme.headlineSmall?.copyWith(color: surfaces.textPrimary)),
                Text(
                  'Zarządzanie serwerami',
                  style: theme.textTheme.bodySmall?.copyWith(color: surfaces.textSecondary),
                ),
                const SizedBox(height: AppSpacing.xl),
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: theme.colorScheme.primary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
