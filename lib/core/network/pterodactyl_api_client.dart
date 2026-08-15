import 'package:dio/dio.dart';

import '../error/app_exception.dart';
import '../error/result.dart';
import 'api_exception_mapper.dart';

/// Low-level HTTP client for talking to a single Pterodactyl Panel instance.
///
/// This class deliberately knows nothing about specific endpoints (servers,
/// files, backups, ...) — it only provides a safe, typed way to perform
/// HTTP requests, and turns every possible failure (network, timeout, HTTP
/// error, malformed body) into a [Result]/[AppException] instead of a raw
/// exception.
///
/// Endpoint-specific API clients built in later steps (e.g. a future
/// `ServersApi`) should be built *on top of* this class rather than reaching
/// for [Dio] directly — this is the seam between "how do we talk HTTP" and
/// "what does the Pterodactyl API look like".
///
/// One instance of [PterodactylApiClient] is scoped to exactly one
/// Pterodactyl instance; see [PterodactylApiClientFactory].
class PterodactylApiClient {
  PterodactylApiClient({
    required Dio dio,
    ApiExceptionMapper exceptionMapper = const ApiExceptionMapper(),
  })  : _dio = dio,
        _exceptionMapper = exceptionMapper;

  final Dio _dio;
  final ApiExceptionMapper _exceptionMapper;

  /// The instance this client talks to. Exposed mainly so tests (and,
  /// later, debug logging) can verify a client was built for the instance
  /// it claims to be — see instance-isolation tests in `features/instances`.
  String get baseUrl => _dio.options.baseUrl;

  Future<Result<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    required T Function(dynamic data) parser,
  }) {
    return _request(
      () => _dio.get<dynamic>(path, queryParameters: queryParameters),
      parser,
    );
  }

  Future<Result<T>> post<T>(
    String path, {
    Object? data,
    required T Function(dynamic data) parser,
  }) {
    return _request(() => _dio.post<dynamic>(path, data: data), parser);
  }

  Future<Result<T>> put<T>(
    String path, {
    Object? data,
    required T Function(dynamic data) parser,
  }) {
    return _request(() => _dio.put<dynamic>(path, data: data), parser);
  }

  Future<Result<T>> delete<T>(
    String path, {
    required T Function(dynamic data) parser,
  }) {
    return _request(() => _dio.delete<dynamic>(path), parser);
  }

  /// Fetches [path] as raw text rather than JSON — the shape the Files
  /// API's `.../files/contents` endpoint actually responds with (a file's
  /// contents, `Content-Type: text/plain`, no `{"data": ...}` envelope).
  /// `responseType: plain` is set explicitly rather than relying on dio's
  /// own content-type sniffing, so this behaves the same regardless of
  /// exactly what `Content-Type` a given Panel/Wings version sends.
  Future<Result<String>> getRawText(String path, {Map<String, dynamic>? queryParameters}) {
    return _request(
      () => _dio.get<String>(
        path,
        queryParameters: queryParameters,
        options: Options(responseType: ResponseType.plain),
      ),
      (data) => data is String ? data : data.toString(),
    );
  }

  /// Sends [content] as a raw `text/plain` body rather than JSON — what
  /// the Files API's `.../files/write` endpoint expects (the file's new
  /// contents directly as the request body, identified by a `?file=`
  /// query parameter, not wrapped in a JSON key).
  Future<Result<void>> postRawText(String path, String content, {Map<String, dynamic>? queryParameters}) {
    return _request(
      () => _dio.post<dynamic>(
        path,
        data: content,
        queryParameters: queryParameters,
        options: Options(contentType: Headers.textPlainContentType),
      ),
      (_) {},
    );
  }

  /// Streams [url]'s response body directly to [savePath] — never buffers
  /// the whole file in memory — reporting progress via
  /// [onReceiveProgress] and cancellable via [cancelToken].
  ///
  /// [url] is frequently an *absolute* URL on a different host than
  /// [baseUrl]: the Files API's `.../files/download` endpoint returns a
  /// one-time signed URL served directly by Wings, not by the Panel this
  /// client is otherwise scoped to (see `FilesApi.getDownloadUrl`). dio
  /// sends an absolute URL exactly as given, ignoring [baseUrl], so this
  /// works for both cases without special-casing which kind of URL it got.
  Future<Result<void>> download({
    required String url,
    required String savePath,
    ProgressCallback? onReceiveProgress,
    CancelToken? cancelToken,
  }) {
    return _request(
      () => _dio.download(url, savePath, onReceiveProgress: onReceiveProgress, cancelToken: cancelToken),
      (_) {},
    );
  }

  /// Uploads the local file at [filePath] as `multipart/form-data` to
  /// [url] (a one-time signed upload URL from `.../files/upload` — see
  /// [download]'s doc comment for why this is often a different host than
  /// [baseUrl]), under form field [fieldName] (`"files"`, matching what
  /// Wings' upload handler expects — see `FilesApi.uploadFile`).
  Future<Result<void>> uploadMultipart({
    required String url,
    required String fieldName,
    required String filePath,
    required String fileName,
    ProgressCallback? onSendProgress,
    CancelToken? cancelToken,
  }) {
    return _request(() async {
      final formData = FormData.fromMap({
        fieldName: await MultipartFile.fromFile(filePath, filename: fileName),
      });
      return _dio.post<dynamic>(url, data: formData, onSendProgress: onSendProgress, cancelToken: cancelToken);
    }, (_) {});
  }

  Future<Result<T>> _request<T>(
    Future<Response<dynamic>> Function() request,
    T Function(dynamic data) parser,
  ) async {
    final Response<dynamic> response;
    try {
      response = await request();
    } catch (error) {
      return Failure<T>(_exceptionMapper.map(error));
    }

    try {
      return Success<T>(parser(response.data));
    } catch (error) {
      return Failure<T>(InvalidResponseException(cause: error));
    }
  }
}
