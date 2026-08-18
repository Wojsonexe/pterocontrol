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
  const NetworkException({super.cause})
      : super(
          'Nie udało się połączyć z serwerem. Sprawdź adres instancji i połączenie z internetem.',
        );
}

/// The server did not respond within the configured timeout.
final class RequestTimeoutException extends AppException {
  const RequestTimeoutException({super.cause}) : super('Serwer nie odpowiedział w wyznaczonym czasie.');
}

/// The stored credentials were rejected (HTTP 401).
final class UnauthorizedException extends AppException {
  const UnauthorizedException({super.cause})
      : super(
          'Sesja wygasła lub klucz API jest nieprawidłowy.',
          statusCode: 401,
        );
}

/// The credentials were valid but do not grant access to this resource
/// (HTTP 403).
final class ForbiddenException extends AppException {
  const ForbiddenException({super.cause})
      : super(
          'Brak uprawnień do wykonania tej operacji.',
          statusCode: 403,
        );
}

/// The requested resource does not exist (HTTP 404).
final class NotFoundException extends AppException {
  const NotFoundException({super.cause}) : super('Nie znaleziono zasobu.', statusCode: 404);
}

/// The request conflicts with the current state of the resource (HTTP
/// 409) — e.g. the Files API rejecting a rename/move/create-folder
/// because something already exists at the destination path.
final class ConflictException extends AppException {
  const ConflictException({super.cause})
      : super('Element o tej nazwie już istnieje.', statusCode: 409);
}

/// The request was well-formed but failed validation (HTTP 422) — e.g.
/// an invalid file/folder name, a path the Files API rejects.
final class ValidationException extends AppException {
  const ValidationException({super.cause})
      : super('Nieprawidłowe dane. Sprawdź nazwę i spróbuj ponownie.', statusCode: 422);
}

/// The server responded with an unexpected error (HTTP 4xx/5xx not covered
/// by a more specific exception above).
final class ServerException extends AppException {
  const ServerException({super.cause, super.statusCode}) : super('Serwer zwrócił nieoczekiwany błąd.');
}

/// The response was received but could not be parsed into the expected
/// shape.
final class InvalidResponseException extends AppException {
  const InvalidResponseException({super.cause}) : super('Odpowiedź serwera ma nieoczekiwany format.');
}

/// A local persistence operation (instance list, preferences, ...) failed.
final class StorageException extends AppException {
  const StorageException(super.message, {super.cause});
}

/// The request was cancelled deliberately (a `CancelToken` the caller
/// itself triggered — e.g. the user tapping "Anuluj" on an in-progress
/// upload/download) — not a failure to report as an error at all. Kept
/// distinct from [UnknownException] specifically so a cancel does not
/// read as "something went wrong" in the UI.
final class CancelledException extends AppException {
  const CancelledException({super.cause}) : super('Anulowano.');
}

/// Fallback for anything that does not fit the categories above.
final class UnknownException extends AppException {
  const UnknownException({super.cause}) : super('Wystąpił nieoczekiwany błąd.');
}
