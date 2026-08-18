import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/network/api_client_config.dart';
import '../../../core/network/interceptors/auth_interceptor.dart';
import 'control_plane_api_client.dart';

/// Builds a [ControlPlaneApiClient] scoped to a single Control Plane
/// backend base URL — mirrors
/// `core/network/api_client_factory.dart`'s shape exactly (same
/// [ApiClientConfig] timeouts, same [AuthInterceptor], same debug-only,
/// header/body-free [LogInterceptor] so a bearer token never ends up in
/// logs) but returns a [ControlPlaneApiClient] instead.
class ControlPlaneApiClientFactory {
  const ControlPlaneApiClientFactory({this.config = const ApiClientConfig()});

  final ApiClientConfig config;

  ControlPlaneApiClient createFor({
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
        LogInterceptor(
          requestBody: false,
          responseBody: false,
          requestHeader: false,
          responseHeader: false,
          logPrint: (object) => debugPrint(object.toString()),
        ),
      );
    }

    return ControlPlaneApiClient(dio: dio);
  }
}
