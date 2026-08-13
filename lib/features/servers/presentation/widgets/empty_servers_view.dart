import 'package:flutter/material.dart';

import '../../../../core/presentation/widgets/empty_state_view.dart';

/// Shown when an instance has no servers.
///
/// Unlike `EmptyInstancesView`, this has no "add" action: creating a
/// server is an admin (Application API) operation Pterodactyl does not
/// expose to the Client API this app uses — a mobile user can only ever
/// see servers already assigned to their account.
class EmptyServersView extends StatelessWidget {
  const EmptyServersView({super.key});

  @override
  Widget build(BuildContext context) {
    return const EmptyStateView(
      icon: Icons.storage_outlined,
      title: 'Brak serwerów',
      message: 'To konto nie ma jeszcze dostępu do żadnego serwera na tej instancji.',
    );
  }
}
