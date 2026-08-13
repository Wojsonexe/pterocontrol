import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// A minimal [HttpClientAdapter] for tests: intercepts every request Dio
/// would otherwise send over the network and replies with whatever
/// [handler] returns (or throws), recording the [RequestOptions] it was
/// last called with so tests can assert on the path/method/headers/query
/// parameters that were actually sent — without a live server or an extra
/// HTTP-mocking package dependency.
class FakeHttpClientAdapter implements HttpClientAdapter {
  FakeHttpClientAdapter(this.handler);

  final FutureOr<ResponseBody> Function(RequestOptions options) handler;

  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

/// Builds a JSON [ResponseBody], the way a real Pterodactyl Panel would
/// (`Content-Type: application/json`).
ResponseBody jsonResponseBody(Object data, {int statusCode = 200}) {
  return ResponseBody.fromString(
    jsonEncode(data),
    statusCode,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

/// Builds an empty [ResponseBody] — e.g. the `204 No Content` the Client
/// API's power endpoint returns, which (unlike [jsonResponseBody]) has no
/// body at all.
ResponseBody emptyResponseBody({int statusCode = 204}) {
  return ResponseBody.fromString('', statusCode);
}
