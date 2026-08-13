import 'app_exception.dart';

/// A value that is either a [Success] or a [Failure].
///
/// Used at layer boundaries (mainly `core/network`) so failures are part of
/// a method's return type instead of being thrown as exceptions that callers
/// might forget to catch. Domain/application code that does not talk to the
/// network directly is free to keep using regular `try`/`catch` with
/// [AppException] where that reads more naturally (e.g. repositories).
sealed class Result<T> {
  const Result();

  /// Runs [onSuccess] or [onFailure] depending on the case, returning
  /// whatever they return.
  R fold<R>({
    required R Function(T value) onSuccess,
    required R Function(AppException error) onFailure,
  }) {
    return switch (this) {
      Success<T>(:final value) => onSuccess(value),
      Failure<T>(:final error) => onFailure(error),
    };
  }

  /// The success value, or `null` if this is a [Failure].
  T? get valueOrNull => switch (this) {
        Success<T>(:final value) => value,
        Failure<T>() => null,
      };

  bool get isSuccess => this is Success<T>;

  bool get isFailure => this is Failure<T>;
}

final class Success<T> extends Result<T> {
  const Success(this.value);

  final T value;
}

final class Failure<T> extends Result<T> {
  const Failure(this.error);

  final AppException error;
}
