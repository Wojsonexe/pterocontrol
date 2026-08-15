import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pterodactyl_mobile/app/app_provider_policy.dart';
import 'package:pterodactyl_mobile/core/error/app_exception.dart';
import 'package:pterodactyl_mobile/core/theme/app_theme.dart';
import 'package:pterodactyl_mobile/features/files/application/files_providers.dart';
import 'package:pterodactyl_mobile/features/files/domain/file_entry.dart';
import 'package:pterodactyl_mobile/features/files/presentation/screens/file_manager_screen.dart';

import '../../../../support/fake_file_repository.dart';

const _target = (instanceId: 'instance-a', serverIdentifier: 'srv-1');

Future<void> _pump(WidgetTester tester, FakeFileRepository repository) async {
  await tester.pumpWidget(
    ProviderScope(
      retry: noAutomaticProviderRetry,
      overrides: [fileRepositoryProvider(_target).overrideWithValue(repository)],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: FileManagerScreen(instanceId: 'instance-a', serverIdentifier: 'srv-1')),
      ),
    ),
  );
}

void main() {
  group('FileManagerScreen', () {
    testWidgets('renders directories and files with their names once loaded', (tester) async {
      final repository = FakeFileRepository();
      repository.directories['/'] = [
        FileEntry(
          name: 'world',
          path: '/world',
          isFile: false,
          isSymlink: false,
          size: 0,
          mimeType: null,
          modifiedAt: DateTime(2026, 1, 1),
        ),
        FileEntry(
          name: 'server.properties',
          path: '/server.properties',
          isFile: true,
          isSymlink: false,
          size: 512,
          mimeType: 'text/plain',
          modifiedAt: DateTime(2026, 1, 1),
        ),
      ];

      await _pump(tester, repository);
      await tester.pump();

      expect(find.text('world'), findsOneWidget);
      expect(find.text('server.properties'), findsOneWidget);
    });

    testWidgets('shows an empty state for an empty directory', (tester) async {
      final repository = FakeFileRepository();
      repository.directories['/'] = [];

      await _pump(tester, repository);
      await tester.pump();

      expect(find.text('Pusty katalog'), findsOneWidget);
    });

    testWidgets('shows an error view with retry when listing fails', (tester) async {
      final repository = FakeFileRepository();
      repository.listErrors['/'] = const ServerException(statusCode: 500);

      await _pump(tester, repository);
      await tester.pump();

      expect(find.text('Serwer zwrócił nieoczekiwany błąd.'), findsOneWidget);
      expect(find.text('Spróbuj ponownie'), findsOneWidget);
    });

    testWidgets('tapping a directory navigates into it', (tester) async {
      final repository = FakeFileRepository();
      repository.directories['/'] = [
        FileEntry(name: 'world', path: '/world', isFile: false, isSymlink: false, size: 0, mimeType: null, modifiedAt: DateTime(2026, 1, 1)),
      ];
      repository.directories['/world'] = [
        FileEntry(
          name: 'level.dat',
          path: '/world/level.dat',
          isFile: true,
          isSymlink: false,
          size: 100,
          mimeType: 'application/octet-stream',
          modifiedAt: DateTime(2026, 1, 1),
        ),
      ];

      await _pump(tester, repository);
      await tester.pump();

      await tester.tap(find.text('world'));
      await tester.pump();

      expect(find.text('level.dat'), findsOneWidget, reason: 'now showing /world\'s contents');
      expect(
        find.text('world'),
        findsOneWidget,
        reason: 'the breadcrumb now shows "world" as the open directory (only the list entry for it is gone)',
      );
    });

    testWidgets('long-pressing an entry enters selection mode showing a count', (tester) async {
      final repository = FakeFileRepository();
      repository.directories['/'] = [
        FileEntry(name: 'a.txt', path: '/a.txt', isFile: true, isSymlink: false, size: 10, mimeType: 'text/plain', modifiedAt: DateTime(2026, 1, 1)),
      ];

      await _pump(tester, repository);
      await tester.pump();

      await tester.longPress(find.text('a.txt'));
      await tester.pump();

      expect(find.text('Wybrano: 1'), findsOneWidget);
    });
  });
}
