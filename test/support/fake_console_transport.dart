import 'dart:async';
import 'dart:convert';

import 'package:pterodactyl_mobile/features/console/data/console_transport.dart';

/// A controllable [ConsoleTransport] for tests: instead of a real
/// WebSocket, the test pushes frames onto [pushFrame]/[pushRaw] and reads
/// what the code under test sent via [sent] — no real socket, no real
/// Internet connection required. Mirrors [FakeHttpClientAdapter]'s role
/// for Dio, applied to the console's streaming transport.
class FakeConsoleTransport implements ConsoleTransport {
  final _controller = StreamController<dynamic>.broadcast();

  /// Every raw frame sent via [send], in order — undecoded, so tests can
  /// assert on the exact JSON shape sent over the wire.
  final List<String> sent = [];

  bool isClosed = false;
  int? _closeCode;
  String? _closeReason;

  @override
  Stream<dynamic> get messages => _controller.stream;

  @override
  Future<void> send(String data) async => sent.add(data);

  @override
  Future<void> close([int? code, String? reason]) async {
    if (isClosed) return;
    isClosed = true;
    _closeCode = code;
    _closeReason = reason;
    await _controller.close();
  }

  @override
  int? get closeCode => _closeCode;

  @override
  String? get closeReason => _closeReason;

  /// Simulates Wings sending `{"event": event, "args": args}`.
  void pushFrame(String event, [List<String> args = const []]) {
    _controller.add(jsonEncode({'event': event, if (args.isNotEmpty) 'args': args}));
  }

  /// Pushes an arbitrary, possibly-malformed raw message (e.g. not JSON,
  /// or not a string at all) — for testing that malformed frames are
  /// dropped rather than crashing anything.
  void pushRaw(dynamic data) => _controller.add(data);

  /// Simulates the remote end (Wings, or the network) closing the
  /// connection unexpectedly, with the given WebSocket close code.
  Future<void> simulateRemoteClose([int? code, String? reason]) async {
    if (isClosed) return;
    isClosed = true;
    _closeCode = code;
    _closeReason = reason;
    await _controller.close();
  }
}

/// Hands out queued [FakeConsoleTransport]s (or throws queued errors) as a
/// [ConsoleTransportConnector], recording every URL it was asked to
/// connect to — so tests can assert reconnect attempts happened, without
/// any of them touching a real network.
class FakeConsoleTransportConnector {
  final List<Uri> requestedUrls = [];
  final _queue = <FutureOr<ConsoleTransport> Function()>[];

  void enqueueTransport(FakeConsoleTransport transport) => _queue.add(() => transport);

  void enqueueError(Object error) => _queue.add(() => throw error);

  ConsoleTransportConnector get connect {
    return (url) async {
      requestedUrls.add(url);
      if (_queue.isEmpty) {
        throw StateError('FakeConsoleTransportConnector: no transport/error queued for $url');
      }
      final produce = _queue.removeAt(0);
      return produce();
    };
  }
}
