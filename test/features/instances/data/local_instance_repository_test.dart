import 'package:flutter_test/flutter_test.dart';
import 'package:pterodactyl_mobile/core/error/app_exception.dart';
import 'package:pterodactyl_mobile/features/instances/data/local_instance_repository.dart';
import 'package:pterodactyl_mobile/features/instances/domain/pterodactyl_instance.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _instanceA = PterodactylInstance(
  id: 'a',
  name: 'Instance A',
  baseUrl: 'https://a.example.com',
);

const _instanceB = PterodactylInstance(
  id: 'b',
  name: 'Instance B',
  baseUrl: 'https://b.example.com',
);

Future<LocalInstanceRepository> _buildRepository() async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  return LocalInstanceRepository(preferences);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalInstanceRepository', () {
    test('getAll returns an empty list when nothing was stored', () async {
      final repository = await _buildRepository();

      expect(await repository.getAll(), isEmpty);
    });

    test('add persists an instance so it is returned by getAll', () async {
      final repository = await _buildRepository();

      await repository.add(_instanceA);

      expect(await repository.getAll(), [_instanceA]);
    });

    test('add throws StorageException when the id already exists', () async {
      final repository = await _buildRepository();
      await repository.add(_instanceA);

      expect(
        () => repository.add(_instanceA),
        throwsA(isA<StorageException>()),
      );
    });

    test('update replaces the stored instance with the same id', () async {
      final repository = await _buildRepository();
      await repository.add(_instanceA);

      final renamed = _instanceA.copyWith(name: 'Renamed');
      await repository.update(renamed);

      expect(await repository.getAll(), [renamed]);
    });

    test('update throws StorageException when the instance does not exist', () async {
      final repository = await _buildRepository();

      expect(
        () => repository.update(_instanceA),
        throwsA(isA<StorageException>()),
      );
    });

    test('remove deletes only the targeted instance', () async {
      final repository = await _buildRepository();
      await repository.add(_instanceA);
      await repository.add(_instanceB);

      await repository.remove(_instanceA.id);

      expect(await repository.getAll(), [_instanceB]);
    });

    test('remove clears the active instance id when it was the removed one', () async {
      final repository = await _buildRepository();
      await repository.add(_instanceA);
      await repository.setActiveInstanceId(_instanceA.id);

      await repository.remove(_instanceA.id);

      expect(await repository.getActiveInstanceId(), isNull);
    });

    test('remove leaves the active instance id untouched otherwise', () async {
      final repository = await _buildRepository();
      await repository.add(_instanceA);
      await repository.add(_instanceB);
      await repository.setActiveInstanceId(_instanceA.id);

      await repository.remove(_instanceB.id);

      expect(await repository.getActiveInstanceId(), _instanceA.id);
    });

    test('active instance id defaults to null and round-trips through set/get', () async {
      final repository = await _buildRepository();

      expect(await repository.getActiveInstanceId(), isNull);

      await repository.setActiveInstanceId(_instanceA.id);
      expect(await repository.getActiveInstanceId(), _instanceA.id);

      await repository.setActiveInstanceId(null);
      expect(await repository.getActiveInstanceId(), isNull);
    });
  });
}
