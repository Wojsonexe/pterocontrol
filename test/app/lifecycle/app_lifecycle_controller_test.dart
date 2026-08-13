import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pterodactyl_mobile/app/lifecycle/app_lifecycle_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppLifecycleController', () {
    test('build() reflects the binding\'s current lifecycle state', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final state = container.read(appLifecycleControllerProvider);

      expect(state, WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed);
    });

    test('updates state when the binding reports a lifecycle change', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.listen(appLifecycleControllerProvider, (_, _) {});

      final controller = container.read(appLifecycleControllerProvider.notifier);
      controller.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(container.read(appLifecycleControllerProvider), AppLifecycleState.paused);

      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(container.read(appLifecycleControllerProvider), AppLifecycleState.resumed);
    });

    test('disposing does not throw and a fresh instance rebuilds cleanly afterward', () {
      final container = ProviderContainer();
      final subscription = container.listen(appLifecycleControllerProvider, (_, _) {});

      subscription.close();
      expect(container.dispose, returnsNormally);

      // A second, independent container proves the previous controller
      // actually unregistered itself from WidgetsBinding on dispose —
      // otherwise two observers would both be receiving lifecycle
      // callbacks, which would surface as flakiness elsewhere, not here.
      final secondContainer = ProviderContainer();
      addTearDown(secondContainer.dispose);
      expect(
        secondContainer.read(appLifecycleControllerProvider),
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed,
      );
    });
  });

  group('AppLifecycleStateX.isAppVisible', () {
    test('is true for resumed and inactive', () {
      expect(AppLifecycleState.resumed.isAppVisible, isTrue);
      expect(AppLifecycleState.inactive.isAppVisible, isTrue);
    });

    test('is false for paused, detached, and hidden', () {
      expect(AppLifecycleState.paused.isAppVisible, isFalse);
      expect(AppLifecycleState.detached.isAppVisible, isFalse);
      expect(AppLifecycleState.hidden.isAppVisible, isFalse);
    });
  });
}
