import 'package:dio/dio.dart';

import '../error/app_exception.dart';

/// Translates transport-level errors (currently: [DioException]) into
/// [AppException]s that the rest of the app knows how to handle and
/// display.
///
/// This is the single place that needs to change if the HTTP client is ever
/// swapped for something other than `dio`.
class ApiExceptionMapper {
  const ApiExceptionMapper();

  AppException map(Object error) {
    if (error is AppException) return error;
    if (error is DioException) return _mapDioException(error);
    return UnknownException(cause: error);
  }

  AppException _mapDioException(DioException error) {
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout =>
        RequestTimeoutException(cause: error),
      DioExceptionType.badResponse => _mapStatusCode(error),
      DioExceptionType.cancel => UnknownException(cause: error),
      // connectionError, badCertificate, unknown, and any future value Dio
      // adds to this enum are all "could not get a usable response" cases.
      _ => NetworkException(cause: error),
    };
  }

  AppException _mapStatusCode(DioException error) {
    final statusCode = error.response?.statusCode;
    return switch (statusCode) {
      401 => UnauthorizedException(cause: error),
      403 => ForbiddenException(cause: error),
      404 => NotFoundException(cause: error),
      _ => ServerException(cause: error, statusCode: statusCode),
    };
  }
}
