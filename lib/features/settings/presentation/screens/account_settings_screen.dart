import 'package:flutter/material.dart';

import '../../../../core/presentation/widgets/coming_soon_view.dart';

/// No `GET /api/client/account` integration exists yet — honest
/// [ComingSoonView] rather than a fabricated profile.
class AccountSettingsScreen extends StatelessWidget {
  const AccountSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Konto')),
      body: const ComingSoonView(
        icon: Icons.person_outline,
        title: 'Profil konta',
        message: 'Podgląd danych konta Pterodactyl pojawi się w kolejnej aktualizacji.',
      ),
    );
  }
}
