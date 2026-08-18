import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pterodactyl_mobile/app/app_provider_policy.dart';
import 'package:pterodactyl_mobile/core/error/app_exception.dart';
import 'package:pterodactyl_mobile/features/files/application/file_editor_controller.dart';
import 'package:pterodactyl_mobile/features/files/application/file_editor_state.dart';
import 'package:pterodactyl_mobile/features/files/application/files_providers.dart';

import '../../../support/fake_file_repository.dart';

const _target = (instanceId: 'instance-a', serverIdentifier: 'srv-1', path: '/server.properties');

({ProviderContainer container, FakeFileRepository repository}) _build() {
  final repository = FakeFileRepository();
  final container = ProviderContainer(
    retry: noAutomaticProviderRetry,
    overrides: [
      fileRepositoryProvider((instanceId: _target.instanceId, serverIdentifier: _target.serverIdentifier))
          .overrideWithValue(repository),
    ],
  );
  return (container: container, repository: repository);
}

void main() {
  group('FileEditorController', () {
    test('loads the file contents on build and starts clean (not dirty)', () async {
      final (:container, :repository) = _build();
      addTearDown(container.dispose);
      repository.fileContents['/server.properties'] = 'server-name=Survival';

      final sub = container.listen(fileEditorControllerProvider(_target), (_, _) {});
      addTearDown(sub.close);
      await pumpEventQueue();

      final state = container.read(fileEditorControllerProvider(_target));
      expect(state.loadStatus, FileEditorLoadStatus.loaded);
      expect(state.currentContent, 'server-name=Survival');
      expect(state.isDirty, isFalse);
    });

    test('a load failure surfaces loadError instead of crashing', () async {
      final (:container, :repository) = _build();
      addTearDown(container.dispose);
      repository.readError = const ForbiddenException();

      final sub = container.listen(fileEditorControllerProvider(_target), (_, _) {});
      addTearDown(sub.close);
      await pumpEventQueue();

      final state = container.read(fileEditorControllerProvider(_target));
      expect(state.loadStatus, FileEditorLoadStatus.error);
      expect(state.loadError, isA<ForbiddenException>());
    });

    test('updateContent() marks the file dirty exactly when it differs from the loaded content', () async {
      final (:container, :repository) = _build();
      addTearDown(container.dispose);
      repository.fileContents['/server.properties'] = 'original';

      final sub = container.listen(fileEditorControllerProvider(_target), (_, _) {});
      addTearDown(sub.close);
      await pumpEventQueue();

      final notifier = container.read(fileEditorControllerProvider(_target).notifier);
      notifier.updateContent('edited');
      expect(container.read(fileEditorControllerProvider(_target)).isDirty, isTrue);

      notifier.updateContent('original');
      expect(
        container.read(fileEditorControllerProvider(_target)).isDirty,
        isFalse,
        reason: 'typing back to the original content is not a real unsaved change',
      );
    });

    test('discardChanges() reverts to the last loaded/saved content', () async {
      final (:container, :repository) = _build();
      addTearDown(container.dispose);
      repository.fileContents['/server.properties'] = 'original';

      final sub = container.listen(fileEditorControllerProvider(_target), (_, _) {});
      addTearDown(sub.close);
      await pumpEventQueue();

      final notifier = container.read(fileEditorControllerProvider(_target).notifier);
      notifier.updateContent('edited but abandoned');
      notifier.discardChanges();

      final state = container.read(fileEditorControllerProvider(_target));
      expect(state.currentContent, 'original');
      expect(state.isDirty, isFalse);
    });

    test('save() writes through the repository and clears isDirty on success', () async {
      final (:container, :repository) = _build();
      addTearDown(container.dispose);
      repository.fileContents['/server.properties'] = 'original';

      final sub = container.listen(fileEditorControllerProvider(_target), (_, _) {});
      addTearDown(sub.close);
      await pumpEventQueue();

      final notifier = container.read(fileEditorControllerProvider(_target).notifier);
      notifier.updateContent('new content');
      final saved = await notifier.save();

      expect(saved, isTrue);
      expect(repository.writeCalls, ['/server.properties']);
      expect(repository.fileContents['/server.properties'], 'new content');
      final state = container.read(fileEditorControllerProvider(_target));
      expect(state.isDirty, isFalse);
      expect(state.saveStatus, FileEditorSaveStatus.saved);
    });

    test('a failed save keeps the unsaved content and isDirty true, and reports the error', () async {
      final (:container, :repository) = _build();
      addTearDown(container.dispose);
      repository.fileContents['/server.properties'] = 'original';
      repository.writeError = const ConflictException();

      final sub = container.listen(fileEditorControllerProvider(_target), (_, _) {});
      addTearDown(sub.close);
      await pumpEventQueue();

      final notifier = container.read(fileEditorControllerProvider(_target).notifier);
      notifier.updateContent('new content');
      final saved = await notifier.save();

      expect(saved, isFalse);
      final state = container.read(fileEditorControllerProvider(_target));
      expect(state.isDirty, isTrue, reason: 'a failed save must not silently drop the user\'s edits');
      expect(state.currentContent, 'new content');
      expect(state.saveStatus, FileEditorSaveStatus.error);
      expect(state.saveError, isA<ConflictException>());
    });
  });
}
