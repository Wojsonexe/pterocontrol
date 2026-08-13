import 'package:dio/dio.dart';

/// Resolves the current bearer token for a request, or `null` if the
/// instance has no stored credentials yet.
///
/// Implemented as a callback (rather than depending on
/// `CredentialStorage` directly) so `core/network` has no knowledge of the
/// `authentication` feature — it only needs "a way to get a token".
typedef AuthTokenProvider = Future<String?> Function();

/// Attaches `Authorization: Bearer <token>` to every outgoing request for a
/// given [PterodactylApiClient], using whatever token [_tokenProvider]
/// currently resolves to.
///
/// Requests are sent without the header if no token is available yet
/// (e.g. an instance added but not yet authenticated) rather than failing
/// client-side — the server is the source of truth for whether that is
/// acceptable.
class AuthInterceptor extends Interceptor {
  AuthInterceptor(this._tokenProvider);

  final AuthTokenProvider _tokenProvider;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await _tokenProvider();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }
}
