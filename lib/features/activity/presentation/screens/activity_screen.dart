import 'package:flutter/material.dart';

import '../../../../core/presentation/widgets/app_top_bar.dart';
import '../../../../core/presentation/widgets/coming_soon_view.dart';

/// "Alerty" tab — server status changes, failed installs, connection
/// loss, and other events worth a push notification. No alerts/events
/// API is wired up yet, so this is an honest [ComingSoonView], not a feed
/// of invented events.
class ActivityScreen extends StatelessWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppTopBar(title: 'Alerty'),
      body: const ComingSoonView(
        icon: Icons.notifications_outlined,
        title: 'Brak alertów',
        message: 'Powiadomienia o zmianach stanu serwerów pojawią się w kolejnej aktualizacji.',
      ),
    );
  }
}
