import 'package:flutter/material.dart';

import '../../theme/app_semantic_colors.dart';
import '../../theme/app_spacing.dart';

/// Generic error placeholder with an optional retry action.
///
/// Takes a plain [message] rather than an `AppException` so `core/`
/// presentation widgets have no dependency on any specific error type —
/// callers are responsible for turning their error into user-facing text
/// (typically just `error.message` when it is an `AppException`).
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final danger = AppSemanticColors.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(color: danger.dangerContainer, shape: BoxShape.circle),
              child: Icon(Icons.error_outline, size: 36, color: danger.onDangerContainer),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(message, style: theme.textTheme.bodyLarge, textAlign: TextAlign.center),
            if (onRetry case final onRetry?) ...[
              const SizedBox(height: AppSpacing.md),
              FilledButton.tonal(onPressed: onRetry, child: const Text('Spróbuj ponownie')),
            ],
          ],
        ),
      ),
    );
  }
}
