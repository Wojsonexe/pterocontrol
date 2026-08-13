/// Base type for every error that is allowed to cross a repository/service
/// boundary in this app.
///
/// Nothing above the data layer (controllers, widgets) should ever catch a
/// [DioException], a [FormatException], or any other transport-specific
/// error directly — those are mapped to an [AppException] first (see
/// `core/network/api_exception_mapper.dart`), so presentation code only
/// ever has one error type to reason about.
sealed class AppException implements Exception {
  const AppException(this.message, {this.cause, this.statusCode});

  /// User-facing (Polish) description of what went wrong.
  final String message;

  /// The original error, kept for logging/debugging. Never shown to users.
  final Object? cause;

  /// HTTP status code, when this exception originated from an HTTP response.
  final int? statusCode;

  @override
  String toString() => message;
}

/// The request never reached the server (no internet, DNS failure, refused
/// connection, ...).
final class NetworkException extends AppException {
  const NetworkException({Object? cause})
      : super(
          'Nie udało się połączyć z serwerem. Sprawdź adres instancji i połączenie z internetem.',
          cause: cause,
        );
}

/// The server did not respond within the configured timeout.
final class RequestTimeoutException extends AppException {
  const RequestTimeoutException({Object? cause})
      : super('Serwer nie odpowiedział w wyznaczonym czasie.', cause: cause);
}

/// The stored credentials were rejected (HTTP 401).
final class UnauthorizedException extends AppException {
  const UnauthorizedException({Object? cause})
      : super(
          'Sesja wygasła lub klucz API jest nieprawidłowy.',
          cause: cause,
          statusCode: 401,
        );
}

/// The credentials were valid but do not grant access to this resource
/// (HTTP 403).
final class ForbiddenException extends AppException {
  const ForbiddenException({Object? cause})
      : super(
          'Brak uprawnień do wykonania tej operacji.',
          cause: cause,
          statusCode: 403,
        );
}

/// The requested resource does not exist (HTTP 404).
final class NotFoundException extends AppException {
  const NotFoundException({Object? cause})
      : super('Nie znaleziono zasobu.', cause: cause, statusCode: 404);
}

/// The server responded with an unexpected error (HTTP 4xx/5xx not covered
/// by a more specific exception above).
final class ServerException extends AppException {
  const ServerException({Object? cause, int? statusCode})
      : super('Serwer zwrócił nieoczekiwany błąd.', cause: cause, statusCode: statusCode);
}

/// The response was received but could not be parsed into the expected
/// shape.
final class InvalidResponseException extends AppException {
  const InvalidResponseException({Object? cause})
      : super('Odpowiedź serwera ma nieoczekiwany format.', cause: cause);
}

/// A local persistence operation (instance list, preferences, ...) failed.
final class StorageException extends AppException {
  const StorageException(super.message, {super.cause});
}

/// Fallback for anything that does not fit the categories above.
final class UnknownException extends AppException {
  const UnknownException({Object? cause}) : super('Wystąpił nieoczekiwany błąd.', cause: cause);
}
