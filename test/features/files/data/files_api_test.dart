import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pterodactyl_mobile/core/network/pterodactyl_api_client.dart';
import 'package:pterodactyl_mobile/features/files/data/files_api.dart';

import '../../../support/fake_http_client_adapter.dart';

({FilesApi api, List<RequestOptions> requests}) _buildApi(
  FutureOr<ResponseBody> Function(RequestOptions options) handler,
) {
  final requests = <RequestOptions>[];
  final adapter = FakeHttpClientAdapter((options) {
    requests.add(options);
    return handler(options);
  });
  final dio = Dio(BaseOptions(baseUrl: 'https://panel.example.com'))..httpClientAdapter = adapter;
  return (api: FilesApi(PterodactylApiClient(dio: dio)), requests: requests);
}

void main() {
  group('FilesApi', () {
    test('list() hits GET .../files/list?directory=... and parses each entry', () async {
      final (:api, :requests) = _buildApi(
        (_) => jsonResponseBody({
          'object': 'list',
          'data': [
            {
              'object': 'file_object',
              'attributes': {
                'name': 'world',
                'size': 0,
                'is_file': false,
                'is_symlink': false,
                'mimetype': 'inode/directory',
                'modified_at': '2026-01-01T00:00:00+00:00',
              },
            },
            {
              'object': 'file_object',
              'attributes': {
                'name': 'server.properties',
                'size': 512,
                'is_file': true,
                'is_symlink': false,
                'mimetype': 'text/plain',
                'modified_at': '2026-01-02T00:00:00+00:00',
              },
            },
          ],
        }),
      );

      final result = await api.list('srv-1', directory: '/');

      expect(requests.single.path, '/api/client/servers/srv-1/files/list');
      expect(requests.single.method, 'GET');
      expect(requests.single.queryParameters['directory'], '/');

      final entries = result.fold(onSuccess: (v) => v, onFailure: (_) => const []);
      expect(entries, hasLength(2));
      expect(entries[0].name, 'world');
      expect(entries[0].isFile, isFalse);
      expect(entries[1].name, 'server.properties');
      expect(entries[1].size, 512);
    });

    test('getContents() hits GET .../files/contents?file=... and returns raw text', () async {
      final (:api, :requests) = _buildApi(
        (_) => ResponseBody.fromString('server-name=Survival', 200, headers: {
          Headers.contentTypeHeader: ['text/plain'],
        }),
      );

      final result = await api.getContents('srv-1', file: '/server.properties');

      expect(requests.single.path, '/api/client/servers/srv-1/files/contents');
      expect(requests.single.queryParameters['file'], '/server.properties');
      expect(result.fold(onSuccess: (v) => v, onFailure: (_) => null), 'server-name=Survival');
    });

    test('writeContents() POSTs the raw body to .../files/write?file=...', () async {
      final (:api, :requests) = _buildApi((_) => emptyResponseBody(statusCode: 204));

      await api.writeContents('srv-1', file: '/server.properties', content: 'server-name=New');

      expect(requests.single.method, 'POST');
      expect(requests.single.path, '/api/client/servers/srv-1/files/write');
      expect(requests.single.queryParameters['file'], '/server.properties');
      expect(requests.single.data, 'server-name=New');
    });

    test('createFolder() POSTs {root, name}', () async {
      final (:api, :requests) = _buildApi((_) => emptyResponseBody(statusCode: 204));
      await api.createFolder('srv-1', root: '/', name: 'backups');
      expect(requests.single.method, 'POST');
      expect(requests.single.path, '/api/client/servers/srv-1/files/create-folder');
      expect(requests.single.data, {'root': '/', 'name': 'backups'});
    });

    test('rename() PUTs {root, files: [{from, to}, ...]} — bulk-capable', () async {
      final (:api, :requests) = _buildApi((_) => emptyResponseBody(statusCode: 204));
      await api.rename(
        'srv-1',
        root: '/',
        files: [(from: 'a.txt', to: 'b.txt'), (from: 'world/c.txt', to: 'backup/c.txt')],
      );
      expect(requests.single.method, 'PUT');
      expect(requests.single.path, '/api/client/servers/srv-1/files/rename');
      expect(requests.single.data, {
        'root': '/',
        'files': [
          {'from': 'a.txt', 'to': 'b.txt'},
          {'from': 'world/c.txt', 'to': 'backup/c.txt'},
        ],
      });
    });

    test('copy() POSTs {location} for exactly one file', () async {
      final (:api, :requests) = _buildApi((_) => emptyResponseBody(statusCode: 204));
      await api.copy('srv-1', location: 'server.properties');
      expect(requests.single.method, 'POST');
      expect(requests.single.path, '/api/client/servers/srv-1/files/copy');
      expect(requests.single.data, {'location': 'server.properties'});
    });

    test('compress() POSTs {root, files} and parses the returned archive entry', () async {
      final (:api, :requests) = _buildApi(
        (_) => jsonResponseBody({
          'object': 'file_object',
          'attributes': {
            'name': 'archive-2026-01-01.tar.gz',
            'size': 1024,
            'is_file': true,
            'is_symlink': false,
            'mimetype': 'application/gzip',
            'modified_at': '2026-01-01T00:00:00+00:00',
          },
        }),
      );

      final result = await api.compress('srv-1', root: '/', files: ['a.txt', 'b.txt']);

      expect(requests.single.data, {
        'root': '/',
        'files': ['a.txt', 'b.txt'],
      });
      final archive = result.fold(onSuccess: (v) => v, onFailure: (_) => null);
      expect(archive!.name, 'archive-2026-01-01.tar.gz');
    });

    test('decompress() POSTs {root, file}', () async {
      final (:api, :requests) = _buildApi((_) => emptyResponseBody(statusCode: 204));
      await api.decompress('srv-1', root: '/', file: 'archive.tar.gz');
      expect(requests.single.data, {'root': '/', 'file': 'archive.tar.gz'});
    });

    test('delete() POSTs {root, files} — bulk-capable', () async {
      final (:api, :requests) = _buildApi((_) => emptyResponseBody(statusCode: 204));
      await api.delete('srv-1', root: '/', files: ['a.txt', 'b.txt']);
      expect(requests.single.data, {
        'root': '/',
        'files': ['a.txt', 'b.txt'],
      });
    });

    test('getDownloadUrl() unwraps a signed_url envelope', () async {
      final built = _buildApi(
        (_) => jsonResponseBody({
          'object': 'signed_url',
          'attributes': {'url': 'https://node1.example.com/download/abc123'},
        }),
      );
      final result = await built.api.getDownloadUrl('srv-1', file: '/server.properties');
      expect(result.fold(onSuccess: (v) => v, onFailure: (_) => null), 'https://node1.example.com/download/abc123');
    });

    test('getUploadUrl() unwraps a signed_url envelope and takes no query parameters', () async {
      final (:api, :requests) = _buildApi(
        (_) => jsonResponseBody({
          'object': 'signed_url',
          'attributes': {'url': 'https://node1.example.com/upload/xyz789'},
        }),
      );
      final result = await api.getUploadUrl('srv-1');
      expect(requests.single.path, '/api/client/servers/srv-1/files/upload');
      expect(result.fold(onSuccess: (v) => v, onFailure: (_) => null), 'https://node1.example.com/upload/xyz789');
    });
  });
}
