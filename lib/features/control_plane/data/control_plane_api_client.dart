import 'package:dio/dio.dart';

import '../../../core/error/app_exception.dart';
import '../../../core/error/result.dart';
import '../../../core/network/api_exception_mapper.dart';

/// Low-level HTTP client for talking to a Control Plane backend
/// (`services/control-plane-api`).
///
/// Deliberately a slimmed-down sibling of
/// `core/network/pterodactyl_api_client.dart` rather than a reuse of it:
/// same `Result`/`AppException` boundary and the same
/// [ApiExceptionMapper], but only `get`/`post` — Control Plane mode has no
/// file upload/download/raw-text needs (no Files API equivalent exists on
/// this backend), so there is nothing to gain from sharing the wider
/// surface, only an import to a class named after a different product.
class ControlPlaneApiClient {
  ControlPlaneApiClient({
    required Dio dio,
    ApiExceptionMapper exceptionMapper = const ApiExceptionMapper(),
  })  : _dio = dio,
        _exceptionMapper = exceptionMapper;

  final Dio _dio;
  final ApiExceptionMapper _exceptionMapper;

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
