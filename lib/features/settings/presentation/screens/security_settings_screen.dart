import 'package:flutter/material.dart';

import '../../../../core/presentation/widgets/coming_soon_view.dart';

/// Biometric app-lock is not implemented yet — honest [ComingSoonView].
class SecuritySettingsScreen extends StatelessWidget {
  const SecuritySettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bezpieczeństwo')),
      body: const ComingSoonView(
        icon: Icons.fingerprint,
        title: 'Blokada biometryczna',
        message: 'Odblokowywanie aplikacji odciskiem palca lub Face ID pojawi się w kolejnej aktualizacji.',
      ),
    );
  }
}
