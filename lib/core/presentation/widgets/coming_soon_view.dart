import 'package:flutter/material.dart';

import 'empty_state_view.dart';

/// Honest "not built yet" state for a feature this app's UI already has a
/// place for (Files, Backups, per-server Startup/Environment settings,
/// Account, Security) but has no backend integration behind — as opposed
/// to [EmptyStateView], which means "this works, there is just nothing to
/// show right now".
///
/// Deliberately never fed fake/generated data — showing this instead is
/// the whole point: a feature with no real API behind it must say so, not
/// pretend to work with made-up content.
class ComingSoonView extends StatelessWidget {
  const ComingSoonView({super.key, required this.icon, required this.title, required this.message});

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return EmptyStateView(icon: icon, title: title, message: message);
  }
}
