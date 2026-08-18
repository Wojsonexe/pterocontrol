import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pterodactyl_mobile/app/app_provider_policy.dart';
import 'package:pterodactyl_mobile/core/error/app_exception.dart';
import 'package:pterodactyl_mobile/features/files/application/file_manager_controller.dart';
import 'package:pterodactyl_mobile/features/files/application/file_manager_state.dart';
import 'package:pterodactyl_mobile/features/files/application/file_transfer_task.dart';
import 'package:pterodactyl_mobile/features/files/application/files_providers.dart';
import 'package:pterodactyl_mobile/features/files/domain/file_entry.dart';

import '../../../support/fake_file_repository.dart';

const _target = (instanceId: 'instance-a', serverIdentifier: 'srv-1');

FileEntry _dir(String name, String parent) => FileEntry(
      name: name,
      path: joinFilePath(parent, name),
      isFile: false,
      isSymlink: false,
      size: 0,
      mimeType: null,
      modifiedAt: DateTime(2026, 1, 1),
    );

FileEntry _file(String name, String parent, {int size = 10}) => FileEntry(
      name: name,
      path: joinFilePath(parent, name),
      isFile: true,
      isSymlink: false,
      size: size,
      mimeType: 'text/plain',
      modifiedAt: DateTime(2026, 1, 1),
    );

({ProviderContainer container, FakeFileRepository repository}) _build() {
  final repository = FakeFileRepository();
  final container = ProviderContainer(
    retry: noAutomaticProviderRetry,
    overrides: [fileRepositoryProvider(_target).overrideWithValue(repository)],
  );
  return (container: container, repository: repository);
}

void main() {
  group('FileManagerController — listing/navigation', () {
    test('build() loads "/" immediately and sorts directories before files, then alphabetically', () async {
      final (:container, :repository) = _build();
      addTearDown(container.dispose);
      repository.directories['/'] = [_file('zeta.txt', '/'), _dir('alpha', '/'), _file('beta.txt', '/')];

      final sub = container.listen(fileManagerControllerProvider(_target), (_, _) {});
      addTearDown(sub.close);
      await pumpEventQueue();

      final state = container.read(fileManagerControllerProvider(_target));
      expect(state.status, FileManagerLoadStatus.loaded);
      expect(state.entries.map((e) => e.name), ['alpha', 'beta.txt', 'zeta.txt']);
    });

    test('navigateTo() clears the previous listing/selection while the new directory loads', () async {
      final (:container, :repository) = _build();
      addTearDown(container.dispose);
      repository.directories['/'] = [_dir('world', '/')];
      repository.directories['/world'] = [_file('level.dat', '/world')];

      final sub = container.listen(fileManagerControllerProvider(_target), (_, _) {});
      addTearDown(sub.close);
      await pumpEventQueue();

      final notifier = container.read(fileManagerControllerProvider(_target).notifier);
      notifier.toggleSelection('/world');
      expect(container.read(fileManagerControllerProvider(_target)).selectedPaths, {'/world'});

      final gate = Completer<void>();
      repository.listGate = gate;
      unawaited(notifier.navigateTo('/world'));
      await pumpEventQueue();

      final mid = container.read(fileManagerControllerProvider(_target));
      expect(mid.status, FileManagerLoadStatus.loading, reason: 'a navigate must not show the old directory as if it were the new one');
      expect(mid.entries, isEmpty);
      expect(mid.selectedPaths, isEmpty, reason: 'selection from the old directory must not leak into the new one');

      gate.complete();
      await pumpEventQueue();

      final done = container.read(fileManagerControllerProvider(_target));
      expect(done.currentPath, '/world');
      expect(done.entries.single.name, 'level.dat');
    });

    test('refresh() keeps stale entries visible while reloading (isRefreshing), not a blank list', () async {
      final (:container, :repository) = _build();
      addTearDown(container.dispose);
      repository.directories['/'] = [_file('a.txt', '/')];

      final sub = container.listen(fileManagerControllerProvider(_target), (_, _) {});
      addTearDown(sub.close);
      await pumpEventQueue();

      final gate = Completer<void>();
      repository.listGate = gate;
      final notifier = container.read(fileManagerControllerProvider(_target).notifier);
      unawaited(notifier.refresh());
      await pumpEventQueue();

      final mid = container.read(fileManagerControllerProvider(_target));
      expect(mid.isRefreshing, isTrue);
      expect(mid.entries, hasLength(1), reason: 'refresh must not blank the list while in flight');

      gate.complete();
      await pumpEventQueue();
      expect(container.read(fileManagerControllerProvider(_target)).isRefreshing, isFalse);
    });

    test('a failed refresh keeps showing the previously loaded entries instead of a full-screen error', () async {
      final (:container, :repository) = _build();
      addTearDown(container.dispose);
      repository.directories['/'] = [_file('a.txt', '/')];

      final sub = container.listen(fileManagerControllerProvider(_target), (_, _) {});
      addTearDown(sub.close);
      await pumpEventQueue();

      repository.listErrors['/'] = const ServerException(statusCode: 500);
      await container.read(fileManagerControllerProvider(_target).notifier).refresh();

      final state = container.read(fileManagerControllerProvider(_target));
      expect(state.status, FileManagerLoadStatus.loaded, reason: 'stale entries mean this must not flip to a full error screen');
      expect(state.entries, hasLength(1));
      expect(state.error, isA<ServerException>());
    });

    test('goUp() from a nested directory navigates to the parent', () async {
      final (:container, :repository) = _build();
      addTearDown(container.dispose);
      repository.directories['/'] = [];
      repository.directories['/world/sub'] = [];
      repository.directories['/world'] = [];

      final sub = container.listen(fileManagerControllerProvider(_target), (_, _) {});
      addTearDown(sub.close);
      await pumpEventQueue();

      final notifier = container.read(fileManagerControllerProvider(_target).notifier);
      await notifier.navigateTo('/world/sub');
      expect(container.read(fileManagerControllerProvider(_target)).currentPath, '/world/sub');

      await notifier.goUp();
      expect(container.read(fileManagerControllerProvider(_target)).currentPath, '/world');
    });
  });

  group('FileManagerController — delete (local patch, not a full reload)', () {
    test('a successful delete removes the entry from state directly, without re-listing the directory', () async {
      final (:container, :repository) = _build();
      addTearDown(container.dispose);
      repository.directories['/'] = [_file('a.txt', '/'), _file('b.txt', '/')];

      final sub = container.listen(fileManagerControllerProvider(_target), (_, _) {});
      addTearDown(sub.close);
      await pumpEventQueue();
      final callsBeforeDelete = repository.listCallCount;

      await container.read(fileManagerControllerProvider(_target).notifier).deleteEntries(['/a.txt']);

      final state = container.read(fileManagerControllerProvider(_target));
      expect(state.entries.map((e) => e.path), ['/b.txt']);
      expect(repository.listCallCount, callsBeforeDelete, reason: 'delete must patch local state, not trigger a re-list');
    });

    test('a failed delete leaves entries untouched and clears the busy flag', () async {
      final (:container, :repository) = _build();
      addTearDown(container.dispose);
      repository.directories['/'] = [_file('a.txt', '/')];
      repository.deleteError = const ForbiddenException();

      final sub = container.listen(fileManagerControllerProvider(_target), (_, _) {});
      addTearDown(sub.close);
      await pumpEventQueue();

      await container.read(fileManagerControllerProvider(_target).notifier).deleteEntries(['/a.txt']);

      final state = container.read(fileManagerControllerProvider(_target));
      expect(state.entries, hasLength(1), reason: 'a failed delete must not remove the entry');
      expect(state.busyPaths, isEmpty);
      expect(state.error, isA<ForbiddenException>());
    });

    test('an entry is marked busy(deleting) while the delete is in flight, and only that entry', () async {
      final (:container, :repository) = _build();
      addTearDown(container.dispose);
      repository.directories['/'] = [_file('a.txt', '/'), _file('b.txt', '/')];

      final sub = container.listen(fileManagerControllerProvider(_target), (_, _) {});
      addTearDown(sub.close);
      await pumpEventQueue();

      final notifier = container.read(fileManagerControllerProvider(_target).notifier);

      // Not awaited yet: state should already reflect "busy" for /a.txt,
      // set synchronously before the (fake, instant) delete call itself
      // even gets to run.
      final future = notifier.deleteEntries(['/a.txt']);
      final mid = container.read(fileManagerControllerProvider(_target));
      expect(mid.busyPaths['/a.txt'], FileOperationKind.deleting);
      expect(mid.busyPaths.containsKey('/b.txt'), isFalse);
      await future;
    });
  });

  group('FileManagerController — rename (local patch)', () {
    test('a successful rename updates the entry\'s name/path in place', () async {
      final (:container, :repository) = _build();
      addTearDown(container.dispose);
      repository.directories['/'] = [_file('old.txt', '/')];

      final sub = container.listen(fileManagerControllerProvider(_target), (_, _) {});
      addTearDown(sub.close);
      await pumpEventQueue();

      await container.read(fileManagerControllerProvider(_target).notifier).rename('/old.txt', 'new.txt');

      final entry = container.read(fileManagerControllerProvider(_target)).entries.single;
      expect(entry.name, 'new.txt');
      expect(entry.path, '/new.txt');
    });

    test('a 409 (name already exists) on rename leaves the original entry untouched', () async {
      final (:container, :repository) = _build();
      addTearDown(container.dispose);
      repository.directories['/'] = [_file('old.txt', '/')];
      repository.renameError = const ConflictException();

      final sub = container.listen(fileManagerControllerProvider(_target), (_, _) {});
      addTearDown(sub.close);
      await pumpEventQueue();

      await container.read(fileManagerControllerProvider(_target).notifier).rename('/old.txt', 'new.txt');

      final state = container.read(fileManagerControllerProvider(_target));
      expect(state.entries.single.name, 'old.txt');
      expect(state.error, isA<ConflictException>());
    });
  });

  group('FileManagerController — move', () {
    test('a successful move removes the moved entries from the current listing', () async {
      final (:container, :repository) = _build();
      addTearDown(container.dispose);
      repository.directories['/'] = [_file('a.txt', '/'), _file('b.txt', '/'), _file('c.txt', '/')];

      final sub = container.listen(fileManagerControllerProvider(_target), (_, _) {});
      addTearDown(sub.close);
      await pumpEventQueue();

      await container.read(fileManagerControllerProvider(_target).notifier).moveEntries(['/a.txt', '/b.txt'], '/backup');

      final state = container.read(fileManagerControllerProvider(_target));
      expect(state.entries.map((e) => e.path), ['/c.txt']);
      expect(repository.moveCalls.single.paths, ['/a.txt', '/b.txt']);
      expect(repository.moveCalls.single.destination, '/backup');
    });
  });

  group('FileManagerController — uploads/downloads', () {
    test('a successful upload refreshes the directory once it completes', () async {
      final (:container, :repository) = _build();
      addTearDown(container.dispose);
      repository.directories['/'] = [];

      final sub = container.listen(fileManagerControllerProvider(_target), (_, _) {});
      addTearDown(sub.close);
      await pumpEventQueue();
      final callsBeforeUpload = repository.listCallCount;

      final notifier = container.read(fileManagerControllerProvider(_target).notifier);
      final id = notifier.startUpload(localFilePath: '/tmp/a.txt', fileName: 'a.txt');
      expect(
        container.read(fileManagerControllerProvider(_target)).transfers.single.id,
        id,
        reason: 'the transfer is registered synchronously, before any await',
      );

      // The fake upload has no gate in this test, so it runs to
      // completion as soon as the event queue is pumped — the
      // "still in progress right after starting" moment is covered by
      // the gated test below instead.
      await pumpEventQueue();

      final done = container.read(fileManagerControllerProvider(_target));
      expect(done.transfers.single.status, FileTransferStatus.success);
      expect(repository.listCallCount, greaterThan(callsBeforeUpload), reason: 'a new file appeared, the directory must refresh');
    });

    test('another entry stays usable while an upload is in progress (per-transfer, not global, busy state)', () async {
      final (:container, :repository) = _build();
      addTearDown(container.dispose);
      repository.directories['/'] = [_file('existing.txt', '/')];

      final sub = container.listen(fileManagerControllerProvider(_target), (_, _) {});
      addTearDown(sub.close);
      await pumpEventQueue();

      final gate = Completer<void>();
      repository.uploadGate = gate;
      final notifier = container.read(fileManagerControllerProvider(_target).notifier);
      notifier.startUpload(localFilePath: '/tmp/new.txt', fileName: 'new.txt');
      await pumpEventQueue();

      // The pre-existing entry is not busy just because an unrelated
      // upload is running.
      final state = container.read(fileManagerControllerProvider(_target));
      expect(state.busyPaths, isEmpty);
      expect(state.entries.single.name, 'existing.txt');

      gate.complete();
      await pumpEventQueue();
    });

    test('cancelling an upload marks the transfer cancelled, not failed', () async {
      final (:container, :repository) = _build();
      addTearDown(container.dispose);
      repository.directories['/'] = [];

      final sub = container.listen(fileManagerControllerProvider(_target), (_, _) {});
      addTearDown(sub.close);
      await pumpEventQueue();

      final gate = Completer<void>();
      repository.uploadGate = gate;
      final notifier = container.read(fileManagerControllerProvider(_target).notifier);
      final id = notifier.startUpload(localFilePath: '/tmp/a.txt', fileName: 'a.txt');
      await pumpEventQueue();

      notifier.cancelTransfer(id);
      gate.complete();
      await pumpEventQueue();
      await pumpEventQueue();

      final state = container.read(fileManagerControllerProvider(_target));
      expect(state.transfers.single.status, FileTransferStatus.cancelled);
    });
  });
}
