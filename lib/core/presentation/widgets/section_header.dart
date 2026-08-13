import 'package:flutter/material.dart';

/// Consistent section title used to visually separate parts of a screen
/// (e.g. `ServerDetailScreen`'s Informacje/Sterowanie/Konsola sections) —
/// replaces ad hoc `Text(..., titleMedium)` calls with no shared wrapper
/// and no consistent trailing-content slot.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
        ?trailing,
      ],
    );
  }
}
