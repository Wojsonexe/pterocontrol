import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_client_config.dart';
import 'interceptors/auth_interceptor.dart';
import 'pterodactyl_api_client.dart';

/// Builds a [PterodactylApiClient] scoped to a single Pterodactyl instance.
///
/// Each call creates its own [Dio] instance (own base URL, own auth
/// interceptor) — clients for different instances never share state, so a
/// mistake in one instance's request can't leak a token or a response into
/// another.
class PterodactylApiClientFactory {
  const PterodactylApiClientFactory({this.config = const ApiClientConfig()});

  final ApiClientConfig config;

  PterodactylApiClient createFor({
    required String baseUrl,
    required AuthTokenProvider authTokenProvider,
  }) {
    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: config.connectTimeout,
        receiveTimeout: config.receiveTimeout,
        sendTimeout: config.sendTimeout,
        headers: const {'Accept': 'application/json'},
      ),
    );

    dio.interceptors.add(AuthInterceptor(authTokenProvider));

    if (kDebugMode) {
      dio.interceptors.add(
        // requestHeader/responseHeader are off deliberately: the request
        // header carries `Authorization: Bearer <token>` and this
        // interceptor prints to the console — a token must never end up
        // there, in debug builds or otherwise.
        //
        // logPrint is routed through Flutter's `debugPrint` explicitly:
        // dio's own default (`_debugPrint` in log.dart) calls plain
        // `print()`, not Flutter's `debugPrint` — using `debugPrint` is
        // dio's own documented recommendation for Flutter apps, and it is
        // also what makes this interceptor's output observable/overridable
        // in tests (see api_client_factory_test.dart).
        LogInterceptor(
          requestBody: false,
          responseBody: false,
          requestHeader: false,
          responseHeader: false,
          logPrint: (object) => debugPrint(object.toString()),
        ),
      );
    }

    return PterodactylApiClient(dio: dio);
  }
}
