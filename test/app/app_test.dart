import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pterodactyl_mobile/app/app.dart';
import 'package:pterodactyl_mobile/app/app_provider_policy.dart';
import 'package:pterodactyl_mobile/core/storage/shared_preferences_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// End-to-end-ish smoke test: builds the real app (real router, real
/// SharedPreferences-backed repository with no data) and exercises the
/// very first thing a brand-new user sees — the welcome screen — through
/// to opening the add-panel wizard from it.
void main() {
  testWidgets('shows the welcome screen and opens the add-panel wizard', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        retry: noAutomaticProviderRetry,
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
        child: const PterodactylMobileApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Twoje serwery.\nZawsze pod ręką.'), findsOneWidget);
    expect(find.text('Połącz panel'), findsOneWidget);

    await tester.tap(find.text('Połącz panel'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Dodaj panel'), findsOneWidget);
    expect(find.text('Adres panelu'), findsOneWidget);
    expect(find.text('Adres URL panelu'), findsOneWidget);
  });
}
