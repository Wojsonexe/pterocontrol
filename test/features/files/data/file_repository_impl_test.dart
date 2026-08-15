import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pterodactyl_mobile/core/error/app_exception.dart';
import 'package:pterodactyl_mobile/core/network/pterodactyl_api_client.dart';
import 'package:pterodactyl_mobile/features/files/data/file_repository_impl.dart';
import 'package:pterodactyl_mobile/features/files/data/files_api.dart';

import '../../../support/fake_http_client_adapter.dart';

({FileRepositoryImpl repository, List<RequestOptions> requests}) _build(
  FutureOr<ResponseBody> Function(RequestOptions options) handler,
) {
  final requests = <RequestOptions>[];
  final adapter = FakeHttpClientAdapter((options) {
    requests.add(options);
    return handler(options);
  });
  final dio = Dio(BaseOptions(baseUrl: 'https://panel.example.com'))..httpClientAdapter = adapter;
  final client = PterodactylApiClient(dio: dio);
  return (
    repository: FileRepositoryImpl(api: FilesApi(client), client: client, serverIdentifier: 'srv-1'),
    requests: requests,
  );
}

void main() {
  group('FileRepositoryImpl — path conventions', () {
    test('listDirectory() joins the requested directory onto each returned name', () async {
      final (:repository, requests: _) = _build(
        (_) => jsonResponseBody({
          'object': 'list',
          'data': [
            {
              'object': 'file_object',
              'attributes': {
                'name': 'server.properties',
                'size': 10,
                'is_file': true,
                'is_symlink': false,
                'mimetype': 'text/plain',
                'modified_at': '2026-01-01T00:00:00+00:00',
              },
            },
          ],
        }),
      );

      final entries = await repository.listDirectory('/world/data');

      expect(entries.single.path, '/world/data/server.properties');
    });

    test('rename() keeps the entry in the same directory (from/to share a parent)', () async {
      final (:repository, :requests) = _build((_) => emptyResponseBody(statusCode: 204));

      await repository.rename('/world/old.txt', 'new.txt');

      final body = requests.single.data as Map;
      expect(body['root'], '/');
      final files = (body['files'] as List).single as Map;
      expect(files['from'], 'world/old.txt');
      expect(files['to'], 'world/new.txt', reason: 'rename must not change the directory');
    });

    test('move() changes the directory but keeps each entry\'s own name, for every entry in one request', () async {
      final (:repository, :requests) = _build((_) => emptyResponseBody(statusCode: 204));

      await repository.move(['/world/a.txt', '/world/sub/b.txt'], '/backup');

      final body = requests.single.data as Map;
      final files = (body['files'] as List).cast<Map>();
      expect(files, hasLength(2), reason: 'a bulk move must be one request, not one per file');
      expect(files[0]['from'], 'world/a.txt');
      expect(files[0]['to'], 'backup/a.txt');
      expect(files[1]['from'], 'world/sub/b.txt');
      expect(files[1]['to'], 'backup/b.txt', reason: 'only the directory changes, not the leaf name');
    });

    test('delete() sends basenames relative to the common parent', () async {
      final (:repository, :requests) = _build((_) => emptyResponseBody(statusCode: 204));

      await repository.delete(['/world/a.txt', '/world/b.txt']);

      final body = requests.single.data as Map;
      expect(body['root'], '/world');
      expect(body['files'], ['a.txt', 'b.txt']);
    });

    test('copyFile() sends the root-relative path, not the leading slash', () async {
      final (:repository, :requests) = _build((_) => emptyResponseBody(statusCode: 204));
      await repository.copyFile('/world/a.txt');
      final body = requests.single.data as Map;
      expect(body['location'], 'world/a.txt');
    });
  });

  group('FileRepositoryImpl — error propagation (throw, not Result)', () {
    test('a 404 from listDirectory throws NotFoundException rather than returning an empty list', () async {
      final (:repository, requests: _) = _build((_) => jsonResponseBody({}, statusCode: 404));
      await expectLater(repository.listDirectory('/missing'), throwsA(isA<NotFoundException>()));
    });

    test('a 409 from createFolder throws ConflictException', () async {
      final (:repository, requests: _) = _build((_) => jsonResponseBody({}, statusCode: 409));
      await expectLater(
        repository.createFolder('/', 'existing-folder'),
        throwsA(isA<ConflictException>()),
      );
    });

    test('a 422 from rename throws ValidationException', () async {
      final (:repository, requests: _) = _build((_) => jsonResponseBody({}, statusCode: 422));
      await expectLater(repository.rename('/a.txt', 'in|valid.txt'), throwsA(isA<ValidationException>()));
    });
  });

  group('FileRepositoryImpl — upload/download', () {
    test('download() streams to savePath and reports success via .done', () async {
      var callCount = 0;
      final (:repository, requests: _) = _build((options) {
        callCount++;
        if (options.path.contains('/files/download')) {
          return jsonResponseBody({
            'object': 'signed_url',
            'attributes': {'url': 'https://panel.example.com/signed/download'},
          });
        }
        return ResponseBody.fromString('file contents here', 200);
      });

      final tempDir = await Directory.systemTemp.createTemp('file_repo_download_test');
      addTearDown(() async {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      });
      final savePath = '${tempDir.path}/out.txt';

      final transfer = repository.download(path: '/server.properties', savePath: savePath);
      await transfer.done;

      expect(await File(savePath).readAsString(), 'file contents here');
      expect(callCount, 2, reason: 'one request for the signed URL, one for the actual bytes');
    });

    test('cancelling an in-flight download surfaces as CancelledException, not a generic error', () async {
      final downloadStarted = Completer<void>();
      final (:repository, requests: _) = _build((options) async {
        if (options.path.contains('/files/download')) {
          return jsonResponseBody({
            'object': 'signed_url',
            'attributes': {'url': 'https://panel.example.com/signed/download'},
          });
        }
        downloadStarted.complete();
        // Never actually completes on its own — the test cancels it.
        await Completer<void>().future;
        return ResponseBody.fromString('unreachable', 200);
      });

      final tempDir = await Directory.systemTemp.createTemp('file_repo_cancel_test');
      addTearDown(() async {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      });

      final transfer = repository.download(path: '/big.log', savePath: '${tempDir.path}/out.txt');
      await downloadStarted.future;
      transfer.handle.cancel();

      await expectLater(transfer.done, throwsA(isA<CancelledException>()));
    });
  });
}
