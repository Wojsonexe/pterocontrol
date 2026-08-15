import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pterodactyl_mobile/core/error/app_exception.dart';
import 'package:pterodactyl_mobile/core/network/pterodactyl_api_client.dart';

import '../../support/fake_http_client_adapter.dart';

/// Exercises the real request/response/exception-mapping path an
/// endpoint-specific API class (e.g. `ServersApi`, `FilesApi`) is built
/// on — a fake HTTP transport stands in for the network, but everything
/// above that (Dio's status validation, [ApiExceptionMapper], the
/// [Result]/[AppException] boundary) is the genuine production code, not
/// re-implemented or stubbed.
PterodactylApiClient _client(FutureOr<ResponseBody> Function(RequestOptions) handler) {
  final dio = Dio(BaseOptions(baseUrl: 'https://panel.example.com'))..httpClientAdapter = FakeHttpClientAdapter(handler);
  return PterodactylApiClient(dio: dio);
}

void main() {
  group('PterodactylApiClient — status code -> AppException mapping', () {
    test('200 -> Success, parser runs on the response body', () async {
      final client = _client((_) => jsonResponseBody({'value': 42}));
      final result = await client.get<int>('/x', parser: (data) => (data as Map<String, dynamic>)['value'] as int);
      expect(result.fold(onSuccess: (v) => v, onFailure: (_) => -1), 42);
    });

    test('401 -> UnauthorizedException', () async {
      final client = _client((_) => jsonResponseBody({}, statusCode: 401));
      final result = await client.get<void>('/x', parser: (_) {});
      expect(result.fold(onSuccess: (_) => null, onFailure: (e) => e), isA<UnauthorizedException>());
    });

    test('403 -> ForbiddenException', () async {
      final client = _client((_) => jsonResponseBody({}, statusCode: 403));
      final result = await client.get<void>('/x', parser: (_) {});
      expect(result.fold(onSuccess: (_) => null, onFailure: (e) => e), isA<ForbiddenException>());
    });

    test('404 -> NotFoundException', () async {
      final client = _client((_) => jsonResponseBody({}, statusCode: 404));
      final result = await client.get<void>('/x', parser: (_) {});
      expect(result.fold(onSuccess: (_) => null, onFailure: (e) => e), isA<NotFoundException>());
    });

    test('409 -> ConflictException (e.g. Files API: name already exists at destination)', () async {
      final client = _client((_) => jsonResponseBody({}, statusCode: 409));
      final result = await client.post<void>('/x', parser: (_) {});
      final error = result.fold(onSuccess: (_) => null, onFailure: (e) => e);
      expect(error, isA<ConflictException>());
      expect(error!.statusCode, 409);
    });

    test('422 -> ValidationException (e.g. Files API: invalid file/folder name)', () async {
      final client = _client((_) => jsonResponseBody({}, statusCode: 422));
      final result = await client.post<void>('/x', parser: (_) {});
      final error = result.fold(onSuccess: (_) => null, onFailure: (e) => e);
      expect(error, isA<ValidationException>());
      expect(error!.statusCode, 422);
    });

    test('500 -> ServerException, statusCode preserved', () async {
      final client = _client((_) => jsonResponseBody({}, statusCode: 500));
      final result = await client.get<void>('/x', parser: (_) {});
      final error = result.fold(onSuccess: (_) => null, onFailure: (e) => e);
      expect(error, isA<ServerException>());
      expect(error!.statusCode, 500);
    });

    test('a body the parser rejects -> InvalidResponseException, not a crash', () async {
      final client = _client((_) => jsonResponseBody({'unexpected': 'shape'}));
      final result = await client.get<int>(
        '/x',
        parser: (data) => throw const FormatException('expected an int'),
      );
      expect(result.fold(onSuccess: (_) => null, onFailure: (e) => e), isA<InvalidResponseException>());
    });
  });

  group('PterodactylApiClient — raw text (Files API contents/write)', () {
    ResponseBody textBody(String text, {int statusCode = 200}) {
      return ResponseBody.fromString(text, statusCode, headers: {
        Headers.contentTypeHeader: ['text/plain'],
      });
    }

    test('getRawText returns the response body as a plain string, not JSON-decoded', () async {
      const contents = 'server-name=Survival\nmax-players=20\n{"not":"json but looks like it"}';
      final client = _client((_) => textBody(contents));

      final result = await client.getRawText('/files/contents');

      expect(result.fold(onSuccess: (v) => v, onFailure: (_) => null), contents);
    });

    test('getRawText maps a 404 (file does not exist) the same way JSON endpoints do', () async {
      final client = _client((_) => textBody('', statusCode: 404));
      final result = await client.getRawText('/files/contents');
      expect(result.fold(onSuccess: (_) => null, onFailure: (e) => e), isA<NotFoundException>());
    });

    test('postRawText sends the string as the body, unmodified', () async {
      RequestOptions? captured;
      final adapter = FakeHttpClientAdapter((options) {
        captured = options;
        return emptyResponseBody(statusCode: 204);
      });
      final dio = Dio(BaseOptions(baseUrl: 'https://panel.example.com'))..httpClientAdapter = adapter;
      final client = PterodactylApiClient(dio: dio);

      final result = await client.postRawText('/files/write', 'line one\nline two');

      expect(result.isSuccess, isTrue);
      expect(captured!.data, 'line one\nline two');
    });
  });

  group('PterodactylApiClient — download', () {
    test('streams the response body to savePath', () async {
      final tempDir = await Directory.systemTemp.createTemp('pterodactyl_download_test');
      addTearDown(() async { try { await tempDir.delete(recursive: true); } catch (_) {} });
      final savePath = '${tempDir.path}/downloaded.txt';

      final client = _client((_) => ResponseBody.fromString('the downloaded file contents', 200));
      final result = await client.download(url: 'https://wings.example.com/download/x', savePath: savePath);

      expect(result.isSuccess, isTrue);
      expect(await File(savePath).readAsString(), 'the downloaded file contents');
    });

    test('a failed download (404) reports NotFoundException and does not leave a partial file mapped as success', () async {
      final tempDir = await Directory.systemTemp.createTemp('pterodactyl_download_test');
      addTearDown(() async { try { await tempDir.delete(recursive: true); } catch (_) {} });
      final savePath = '${tempDir.path}/downloaded.txt';

      final client = _client((_) => ResponseBody.fromString('not found', 404));
      final result = await client.download(url: 'https://wings.example.com/download/x', savePath: savePath);

      expect(result.fold(onSuccess: (_) => null, onFailure: (e) => e), isA<NotFoundException>());
    });
  });

  group('PterodactylApiClient — uploadMultipart', () {
    test('uploads the file as multipart/form-data under the given field name', () async {
      final tempDir = await Directory.systemTemp.createTemp('pterodactyl_upload_test');
      addTearDown(() async { try { await tempDir.delete(recursive: true); } catch (_) {} });
      final sourceFile = File('${tempDir.path}/to-upload.txt')..writeAsStringSync('upload me');

      RequestOptions? captured;
      final adapter = FakeHttpClientAdapter((options) {
        captured = options;
        return jsonResponseBody({});
      });
      final dio = Dio(BaseOptions(baseUrl: 'https://panel.example.com'))..httpClientAdapter = adapter;
      final client = PterodactylApiClient(dio: dio);

      final result = await client.uploadMultipart(
        url: 'https://wings.example.com/upload/x',
        fieldName: 'files',
        filePath: sourceFile.path,
        fileName: 'to-upload.txt',
      );

      expect(result.isSuccess, isTrue);
      expect(captured!.data, isA<FormData>());
      final formData = captured!.data as FormData;
      expect(formData.files, hasLength(1));
      expect(formData.files.single.key, 'files');
      expect(formData.files.single.value.filename, 'to-upload.txt');
    });
  });
}
