import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../../servers/domain/server_power_state.dart';
import '../../servers/domain/server_runtime_state.dart';
import '../domain/console_connection_state.dart';
import '../domain/console_event.dart';
import '../domain/console_repository.dart';
import 'console_api.dart';
import 'console_protocol_events.dart';
import 'console_protocol_message.dart';
import 'console_transport.dart';
import 'console_websocket_client.dart';

/// How long to wait for `auth success` after sending `auth` before giving
/// up on the attempt. Wings responds essentially immediately on a healthy
/// connection; without this bound, a connection that opens but never
/// replies (a misbehaving proxy, a Wings instance stuck mid-restart) would
/// leave the repository stuck in `connecting` forever instead of retrying.
const kConsoleAuthTimeout = Duration(seconds: 10);

/// Wings close codes that must **not** trigger a reconnect attempt.
///
/// Verified against `wings/router/router_server_ws.go`'s
/// `expectedCloseCodes`/suspension handling and mirrored by the reference
/// Panel frontend (`WebsocketHandler.tsx`'s `onreconnect` skip list):
/// 4409 = server suspended, 4400 = reserved/graceful-shutdown-style code
/// Wings itself uses for conditions that will not resolve by retrying.
const _noRetryCloseCodes = {4409, 4400};

/// JWT error messages (substring match, case-insensitive) that are
/// recoverable by fetching a fresh token and re-authenticating on the
/// *same* socket, rather than being treated as fatal.
///
/// Verified against the reference Panel frontend
/// (`WebsocketHandler.tsx`'s `reconnectErrors` list) — every other
/// `jwt error` message (missing token, missing permission, server UUID
/// mismatch) is fatal and not worth retrying automatically.
const _refreshableJwtErrorSubstrings = [
  'jwt: exp claim is invalid',
  'jwt: created too far in past (denylist)',
];

/// Base reconnect schedule: 1s, 2s, 4s, 8s, 16s, then capped at 30s.
///
/// A plain function (not a method) so tests can substitute a
/// near-instant schedule instead of waiting on real timers, and so the
/// schedule itself is unit-testable in isolation from any connection
/// logic. Deliberately kept deterministic/unjittered — [_jitteredBackoff]
/// (this repository's actual default) wraps it; this one stays exact so
/// "what does attempt N nominally wait" remains simple to assert in
/// tests and reason about on its own.
Duration defaultConsoleReconnectBackoff(int attempt) {
  final steps = attempt.clamp(0, 5);
  final seconds = 1 << steps; // 1, 2, 4, 8, 16, 32
  return Duration(seconds: seconds > 30 ? 30 : seconds);
}

/// "Equal jitter" (base/2 fixed + up to base/2 random) over
/// [defaultConsoleReconnectBackoff] — the actual default schedule
/// [ConsoleRepositoryImpl] reconnects on.
///
/// Plain exponential backoff alone still synchronizes every device that
/// dropped its connection at the same moment (a Wings restart, a node
/// network blip) onto the *same* retry instants, which just moves the
/// thundering herd from t=0 to t=1s, t=2s, .... Equal jitter keeps the
/// schedule's growth guarantee (attempt N+1 never waits less than
/// attempt N's minimum) while spreading concurrent retries across a
/// window instead of a single instant — the same strategy AWS's
/// architecture blog recommends over "full" jitter (which can let a late
/// attempt roll a delay as short as attempt 0's).
///
/// [random] is injectable so a test can assert the resulting range is
/// exactly `[base/2, base]` without depending on real randomness.
Duration jitteredConsoleReconnectBackoff(int attempt, {Random? random}) {
  final base = defaultConsoleReconnectBackoff(attempt);
  final halfMs = base.inMilliseconds ~/ 2;
  if (halfMs <= 0) return base;
  final jitterMs = (random ?? _sharedRandom).nextInt(halfMs + 1);
  return Duration(milliseconds: halfMs + jitterMs);
}

final _sharedRandom = Random();

/// Real [ConsoleRepository]: fetches a websocket token via [ConsoleApi],
/// opens a [ConsoleTransport] (production: a real WebSocket; tests: a
/// fake), authenticates, and turns Wings frames into this app's domain
/// streams.
///
/// One instance per `ConsoleTarget` (one server on one instance) — see
/// `ConsoleRepository`'s doc comment. Never shares a transport, token, or
/// buffer with any other target.
class ConsoleRepositoryImpl implements ConsoleRepository {
  ConsoleRepositoryImpl({
    required ConsoleApi api,
    required String serverIdentifier,
    required ConsoleTransportConnector transportConnector,
    Duration Function(int attempt)? backoffForAttempt,
    int maxBufferSize = 500,
  })  : _api = api,
        _serverIdentifier = serverIdentifier,
        _transportConnector = transportConnector,
        _backoffForAttempt = backoffForAttempt ?? jitteredConsoleReconnectBackoff,
        _maxBufferSize = maxBufferSize,
        assert(maxBufferSize > 0, 'maxBufferSize must be positive');

  final ConsoleApi _api;
  final String _serverIdentifier;
  final ConsoleTransportConnector _transportConnector;
  final Duration Function(int attempt) _backoffForAttempt;

  /// Caps the console buffer so a long-running session (or a chatty
  /// server) cannot grow memory unbounded. 500 lines is comfortably more
  /// than a terminal viewport ever shows at once while staying small
  /// (well under 1MB of `String` data in the worst realistic case).
  final int _maxBufferSize;

  final _connectionStateController = StreamController<ConsoleConnectionState>.broadcast();
  final _runtimeStateController = StreamController<ServerRuntimeState>.broadcast();
  final _eventsController = StreamController<List<ConsoleEvent>>.broadcast();

  final List<ConsoleEvent> _buffer = [];

  ConsoleWebSocketClient? _client;
  StreamSubscription<ConsoleProtocolMessage>? _messageSubscription;
  Timer? _reconnectTimer;
  Timer? _authTimeoutTimer;

  /// `true` between a [connect] call and either [disconnect] or a
  /// terminal failure (non-refreshable `jwt error`, a no-retry close
  /// code). Reconnect attempts only ever happen while this is `true` —
  /// this is what makes "no reconnect after intentional disconnect" and
  /// "no infinite tight loop after a fatal error" hold.
  bool _connectRequested = false;

  /// `true` once `auth success` has been received for the *current*
  /// transport. Gates [sendCommand] and decides whether an inbound frame
  /// arrived on a live, authenticated session.
  bool _authenticated = false;

  /// `true` until the first successful auth on the *current* transport.
  /// Distinguishes a genuine (re)connect — clear the buffer, re-request
  /// backlog via `send logs` — from a same-socket token refresh
  /// (`token expiring`/`token expired`/refreshable `jwt error`), where
  /// Wings does not re-send `status` and neither should the client touch
  /// the buffer. Mirrors Wings' own `newConnection := h.GetJwt() == nil`
  /// check in `wings/router/websocket/websocket.go`.
  bool _freshConnection = true;

  bool _disposed = false;
  bool _refreshingToken = false;
  int _attempt = 0;

  @override
  Stream<ConsoleConnectionState> get connectionState => _connectionStateController.stream;

  @override
  Stream<ServerRuntimeState> get runtimeState => _runtimeStateController.stream;

  @override
  Stream<List<ConsoleEvent>> get events => _eventsController.stream;

  @override
  Future<void> connect() async {
    if (_disposed || _connectRequested) return;
    _connectRequested = true;
    _attempt = 0;
    _reconnectTimer?.cancel();
    unawaited(_attemptConnect());
  }

  @override
  Future<void> disconnect() async {
    _connectRequested = false;
    _reconnectTimer?.cancel();
    await _teardownClient();
    _setConnectionState(ConsoleConnectionState.disconnected);
  }

  @override
  void sendCommand(String command) {
    if (!_authenticated) return;
    unawaited(_client?.send(ConsoleProtocolEvent.sendCommand, [command]));
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _connectRequested = false;
    _reconnectTimer?.cancel();
    await _teardownClient();
    await _connectionStateController.close();
    await _runtimeStateController.close();
    await _eventsController.close();
  }

  Future<void> _teardownClient() async {
    _authTimeoutTimer?.cancel();
    _authTimeoutTimer = null;
    await _messageSubscription?.cancel();
    _messageSubscription = null;
    final client = _client;
    _client = null;
    _authenticated = false;
    if (client != null) {
      await client.close();
      await client.dispose();
    }
  }

  Future<void> _attemptConnect() async {
    if (_disposed || !_connectRequested) return;
    if (_attempt == 0) {
      _setConnectionState(ConsoleConnectionState.connecting);
    }

    final tokenResult = await _api.getWebsocketToken(_serverIdentifier);
    if (_disposed || !_connectRequested) return;

    final tokenDto = tokenResult.valueOrNull;
    if (tokenDto == null) {
      _scheduleReconnect();
      return;
    }

    final Uri url;
    try {
      url = Uri.parse(tokenDto.socketUrl);
    } on FormatException {
      _scheduleReconnect();
      return;
    }

    final ConsoleTransport transport;
    try {
      transport = await _transportConnector(url);
    } catch (_) {
      if (_disposed || !_connectRequested) return;
      _scheduleReconnect();
      return;
    }
    if (_disposed || !_connectRequested) {
      unawaited(transport.close());
      return;
    }

    final client = ConsoleWebSocketClient(transport);
    _client = client;
    _freshConnection = true;
    _messageSubscription = client.messages.listen(_handleProtocolMessage);
    unawaited(client.done.then((_) => _handleTransportClosed(client)));

    // The transport itself is open at this point — what's left is Wings'
    // own `auth`/`auth success` round trip, a distinct failure mode from
    // "could not open a socket at all" (see `ConsoleConnectionState`'s
    // doc comment). Set regardless of attempt number: a reconnect that
    // gets this far should stop reading as "reconnecting" the moment
    // there is something more specific to report.
    _setConnectionState(ConsoleConnectionState.authenticating);
    await client.send(ConsoleProtocolEvent.auth, [tokenDto.token]);

    _authTimeoutTimer?.cancel();
    _authTimeoutTimer = Timer(kConsoleAuthTimeout, () {
      if (_client == client && !_authenticated) {
        unawaited(client.close());
      }
    });
  }

  void _handleProtocolMessage(ConsoleProtocolMessage message) {
    switch (message.event) {
      case ConsoleProtocolEvent.authSuccess:
        _handleAuthSuccess();
      case ConsoleProtocolEvent.jwtError:
        _handleJwtError(message.joinedArgs);
      case ConsoleProtocolEvent.tokenExpiring:
      case ConsoleProtocolEvent.tokenExpired:
        unawaited(_refreshToken());
      case ConsoleProtocolEvent.consoleOutput:
      case ConsoleProtocolEvent.installOutput:
        _appendEvent(ConsoleEventType.output, message.joinedArgs);
      case ConsoleProtocolEvent.daemonMessage:
        _appendEvent(ConsoleEventType.daemonMessage, message.joinedArgs);
      case ConsoleProtocolEvent.daemonError:
        _appendEvent(ConsoleEventType.daemonError, message.joinedArgs);
      case ConsoleProtocolEvent.status:
        _handleStatus(message.joinedArgs);
      case ConsoleProtocolEvent.stats:
        // Wings broadcasts this continuously (every few seconds) for a
        // running server — CPU/memory/disk telemetry, the same feed that
        // drives the Panel's live resource graphs. Deliberately not
        // appended to the console buffer (it would otherwise flood the
        // terminal with a "stats" line every tick — see README, "Konsola
        // live przez WebSocket") — instead parsed and pushed onto
        // [runtimeState], the same stream `_handleStatus` feeds, so a
        // connected console gives the richest, lowest-latency runtime
        // reading available (seconds, not the ~30s REST poll cadence of
        // `ServerRuntimeSyncController`).
        _handleStats(message.joinedArgs);
      default:
        // Anything else (`backup completed:<uuid>`, `transfer
        // logs`/`transfer status`, `install started`/`install completed`,
        // `deleted`, `throttled`, or any future event Wings adds) is kept
        // rather than crashing the console or silently vanishing.
        _appendEvent(ConsoleEventType.unknown, message.event);
    }
  }

  void _handleAuthSuccess() {
    _authTimeoutTimer?.cancel();
    _authenticated = true;
    _attempt = 0;
    _setConnectionState(ConsoleConnectionState.connected);
    if (_freshConnection) {
      _freshConnection = false;
      _clearBuffer();
      unawaited(_client?.send(ConsoleProtocolEvent.sendLogs));
    }
  }

  void _handleJwtError(String message) {
    final lower = message.toLowerCase();
    final isRefreshable = _refreshableJwtErrorSubstrings.any(lower.contains);
    if (isRefreshable) {
      unawaited(_refreshToken());
      return;
    }
    // Not recoverable by refreshing (bad/missing permission, server UUID
    // mismatch, ...) — stop retrying automatically, matching the
    // reference client's treatment of these as fatal. A caller can still
    // start over with a fresh connect().
    _connectRequested = false;
    _setConnectionState(ConsoleConnectionState.error);
    unawaited(_teardownClient());
  }

  Future<void> _refreshToken() async {
    if (_refreshingToken || _disposed || !_connectRequested) return;
    final client = _client;
    if (client == null) return;
    _refreshingToken = true;
    try {
      final result = await _api.getWebsocketToken(_serverIdentifier);
      if (_disposed || !_connectRequested || _client != client) return;
      final tokenDto = result.valueOrNull;
      if (tokenDto == null) {
        // Transient REST failure — leave the existing connection running;
        // Wings will emit another `token expiring` tick (or eventually
        // `token expired`/`jwt error`) that gives this another chance.
        return;
      }
      await client.send(ConsoleProtocolEvent.auth, [tokenDto.token]);
      // Re-auth on the same socket: `_freshConnection` stays false, so
      // `_handleAuthSuccess` will not clear the buffer or re-request
      // backlog — Wings does not re-send `status` for this either.
    } finally {
      _refreshingToken = false;
    }
  }

  void _handleStatus(String rawState) {
    _runtimeStateController.add(
      ServerRuntimeState(powerState: _powerStateFromRaw(rawState), observedAt: DateTime.now()),
    );
  }

  /// Parses a `stats` frame's joined args — a JSON-encoded
  /// `wings/server.ResourceUsage` (`environment.Stats` embedded, plus
  /// `state`/`disk_bytes`; verified against `wings/environment/stats.go`
  /// and `wings/server/resources.go`) — into a [ServerRuntimeState] and
  /// pushes it onto [runtimeState] alongside [_handleStatus]'s updates.
  void _handleStats(String rawJson) {
    final Object? decoded;
    try {
      decoded = jsonDecode(rawJson);
    } on FormatException {
      // A malformed frame must not crash the console session — Wings
      // sends another `stats` tick a few seconds later regardless.
      return;
    }
    if (decoded is! Map<String, dynamic>) return;

    final rawState = decoded['state'];
    final network = decoded['network'];

    _runtimeStateController.add(
      ServerRuntimeState(
        powerState: rawState is String ? _powerStateFromRaw(rawState) : ServerPowerState.unknown,
        observedAt: DateTime.now(),
        cpuAbsolutePercent: (decoded['cpu_absolute'] as num?)?.toDouble(),
        memoryBytes: (decoded['memory_bytes'] as num?)?.toInt(),
        diskBytes: (decoded['disk_bytes'] as num?)?.toInt(),
        networkRxBytes: network is Map ? (network['rx_bytes'] as num?)?.toInt() : null,
        networkTxBytes: network is Map ? (network['tx_bytes'] as num?)?.toInt() : null,
        uptimeMs: (decoded['uptime'] as num?)?.toInt(),
      ),
    );
  }

  /// Same mapping `ServerRepositoryImpl` applies to the REST
  /// `.../resources` response's `current_state` — both read the exact set
  /// of strings Wings emits for the same underlying power state, just over
  /// different transports.
  ServerPowerState _powerStateFromRaw(String raw) {
    return switch (raw) {
      'offline' => ServerPowerState.offline,
      'starting' => ServerPowerState.starting,
      'running' => ServerPowerState.running,
      'stopping' => ServerPowerState.stopping,
      _ => ServerPowerState.unknown,
    };
  }

  void _handleTransportClosed(ConsoleWebSocketClient client) {
    if (_client != client) return; // already superseded by a newer attempt
    final closeCode = client.closeCode;
    unawaited(_teardownClient());

    if (_disposed || !_connectRequested) {
      _setConnectionState(ConsoleConnectionState.disconnected);
      return;
    }

    if (closeCode != null && _noRetryCloseCodes.contains(closeCode)) {
      _connectRequested = false;
      _setConnectionState(ConsoleConnectionState.error);
      return;
    }

    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed || !_connectRequested) {
      _setConnectionState(ConsoleConnectionState.disconnected);
      return;
    }
    _setConnectionState(ConsoleConnectionState.reconnecting);
    final delay = _backoffForAttempt(_attempt);
    _attempt++;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      if (_disposed || !_connectRequested) return;
      unawaited(_attemptConnect());
    });
  }

  void _appendEvent(ConsoleEventType type, String message) {
    _buffer.add(ConsoleEvent(type: type, message: message, timestamp: DateTime.now()));
    while (_buffer.length > _maxBufferSize) {
      _buffer.removeAt(0);
    }
    if (!_eventsController.isClosed) {
      _eventsController.add(List.unmodifiable(_buffer));
    }
  }

  void _clearBuffer() {
    _buffer.clear();
    if (!_eventsController.isClosed) {
      _eventsController.add(const []);
    }
  }

  void _setConnectionState(ConsoleConnectionState state) {
    if (!_connectionStateController.isClosed) {
      _connectionStateController.add(state);
    }
  }
}
