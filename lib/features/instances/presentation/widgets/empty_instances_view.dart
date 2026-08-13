import 'package:flutter/material.dart';

import '../../../../core/presentation/widgets/empty_state_view.dart';

class EmptyInstancesView extends StatelessWidget {
  const EmptyInstancesView({super.key, required this.onAddInstance});

  final VoidCallback onAddInstance;

  @override
  Widget build(BuildContext context) {
    return EmptyStateView(
      icon: Icons.dns_outlined,
      title: 'Brak dodanych instancji',
      message: 'Dodaj instancję Pterodactyl Panel, aby zarządzać serwerami z telefonu.',
      action: FilledButton.icon(
        onPressed: onAddInstance,
        icon: const Icon(Icons.add),
        label: const Text('Dodaj instancję'),
      ),
    );
  }
}
