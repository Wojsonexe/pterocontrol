import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pterodactyl_mobile/core/error/app_exception.dart';
import 'package:pterodactyl_mobile/core/network/pterodactyl_api_client.dart';
import 'package:pterodactyl_mobile/features/servers/data/servers_api.dart';
import 'package:pterodactyl_mobile/features/servers/domain/server_power_action.dart';

import '../../../support/fake_http_client_adapter.dart';

Map<String, dynamic> _serverItemJson() => {
      'object': 'server',
      'attributes': {
        'identifier': 'd3aac109',
        'uuid': 'd3aac109-e5e0-4331-b03e-3454f7e660f1',
        'name': 'My Server',
        'description': '',
        'node': 'Node 1',
        'status': null,
        'is_transferring': false,
        'limits': {'memory': 1024, 'disk': 5120, 'cpu': 100},
      },
    };

Map<String, dynamic> _resourcesJson({String currentState = 'running'}) => {
      'object': 'stats',
      'attributes': {
        'current_state': currentState,
        'is_suspended': false,
        'resources': {
          'memory_bytes': 512000000,
          'cpu_absolute': 12.5,
          'disk_bytes': 1024000000,
          'network_rx_bytes': 2048,
          'network_tx_bytes': 4096,
          'uptime': 3600000,
        },
      },
    };

Map<String, dynamic> _pageJson({int currentPage = 1, int totalPages = 1}) => {
      'object': 'list',
      'data': [
        {
          'object': 'server',
          'attributes': {
            'identifier': 'd3aac109',
            'uuid': 'd3aac109-e5e0-4331-b03e-3454f7e660f1',
            'name': 'My Server',
            'description': '',
            'node': 'Node 1',
            'status': null,
            'is_transferring': false,
            'limits': {'memory': 1024, 'disk': 5120, 'cpu': 100},
          },
        },
      ],
      'meta': {
        'pagination': {
          'total': 1,
          'count': 1,
          'per_page': 50,
          'current_page': currentPage,
          'total_pages': totalPages,
        },
      },
    };

ServersApi _buildApi(FakeHttpClientAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://panel.example.com'))..httpClientAdapter = adapter;
  return ServersApi(PterodactylApiClient(dio: dio));
}

void main() {
  group('ServersApi.getServers', () {
    test('sends GET /api/client with the requested page as a query parameter', () async {
      final adapter = FakeHttpClientAdapter((options) async => jsonResponseBody(_pageJson()));
      final api = _buildApi(adapter);

      await api.getServers(page: 2);

      expect(adapter.lastRequest?.method, 'GET');
      expect(adapter.lastRequest?.path, '/api/client');
      expect(adapter.lastRequest?.queryParameters['page'], 2);
    });

    test('maps a successful response into ServerDto list and pagination meta', () async {
      final adapter = FakeHttpClientAdapter(
        (options) async => jsonResponseBody(_pageJson(currentPage: 1, totalPages: 3)),
      );
      final api = _buildApi(adapter);

      final result = await api.getServers();

      final data = result.fold(onSuccess: (value) => value, onFailure: (error) => throw error);
      expect(data.servers, hasLength(1));
      expect(data.servers.single.identifier, 'd3aac109');
      expect(data.servers.single.name, 'My Server');
      expect(data.meta.currentPage, 1);
      expect(data.meta.totalPages, 3);
      expect(data.meta.hasNextPage, isTrue);
    });

    test('maps an HTTP 401 response to UnauthorizedException', () async {
      final adapter = FakeHttpClientAdapter(
        (options) async => jsonResponseBody({'errors': []}, statusCode: 401),
      );
      final api = _buildApi(adapter);

      final result = await api.getServers();

      expect(result.isFailure, isTrue);
      result.fold(
        onSuccess: (_) => fail('expected a failure'),
        onFailure: (error) => expect(error, isA<UnauthorizedException>()),
      );
    });

    test('maps an HTTP 500 response to ServerException', () async {
      final adapter = FakeHttpClientAdapter(
        (options) async => jsonResponseBody({'errors': []}, statusCode: 500),
      );
      final api = _buildApi(adapter);

      final result = await api.getServers();

      result.fold(
        onSuccess: (_) => fail('expected a failure'),
        onFailure: (error) => expect(error, isA<ServerException>()),
      );
    });

    test('maps a receive timeout to RequestTimeoutException', () async {
      final adapter = FakeHttpClientAdapter(
        (options) async => throw DioException(requestOptions: options, type: DioExceptionType.receiveTimeout),
      );
      final api = _buildApi(adapter);

      final result = await api.getServers();

      result.fold(
        onSuccess: (_) => fail('expected a failure'),
        onFailure: (error) => expect(error, isA<RequestTimeoutException>()),
      );
    });

    test('maps a malformed body to InvalidResponseException instead of crashing', () async {
      final adapter = FakeHttpClientAdapter(
        (options) async => jsonResponseBody({'object': 'list', 'data': 'not-a-list'}),
      );
      final api = _buildApi(adapter);

      final result = await api.getServers();

      result.fold(
        onSuccess: (_) => fail('expected a failure'),
        onFailure: (error) => expect(error, isA<InvalidResponseException>()),
      );
    });
  });

  group('ServersApi.getServer', () {
    test('sends GET /api/client/servers/{server} and maps the response into a ServerDto', () async {
      final adapter = FakeHttpClientAdapter((options) async => jsonResponseBody(_serverItemJson()));
      final api = _buildApi(adapter);

      final result = await api.getServer('d3aac109');

      expect(adapter.lastRequest?.method, 'GET');
      expect(adapter.lastRequest?.path, '/api/client/servers/d3aac109');
      final dto = result.fold(onSuccess: (value) => value, onFailure: (error) => throw error);
      expect(dto.identifier, 'd3aac109');
      expect(dto.name, 'My Server');
    });

    test('maps an HTTP 404 response to NotFoundException', () async {
      final adapter = FakeHttpClientAdapter((options) async => jsonResponseBody({'errors': []}, statusCode: 404));
      final api = _buildApi(adapter);

      final result = await api.getServer('missing');

      result.fold(
        onSuccess: (_) => fail('expected a failure'),
        onFailure: (error) => expect(error, isA<NotFoundException>()),
      );
    });
  });

  group('ServersApi.getResourceUsage', () {
    test('sends GET /api/client/servers/{server}/resources and maps the response', () async {
      final adapter = FakeHttpClientAdapter(
        (options) async => jsonResponseBody(_resourcesJson(currentState: 'running')),
      );
      final api = _buildApi(adapter);

      final result = await api.getResourceUsage('d3aac109');

      expect(adapter.lastRequest?.method, 'GET');
      expect(adapter.lastRequest?.path, '/api/client/servers/d3aac109/resources');
      final dto = result.fold(onSuccess: (value) => value, onFailure: (error) => throw error);
      expect(dto.currentState, 'running');
      expect(dto.cpuAbsolutePercent, 12.5);
      expect(dto.memoryBytes, 512000000);
      expect(dto.diskBytes, 1024000000);
      expect(dto.networkRxBytes, 2048);
      expect(dto.networkTxBytes, 4096);
      expect(dto.uptimeMs, 3600000);
    });

    test('maps an HTTP 500 response to ServerException', () async {
      final adapter = FakeHttpClientAdapter((options) async => jsonResponseBody({'errors': []}, statusCode: 500));
      final api = _buildApi(adapter);

      final result = await api.getResourceUsage('d3aac109');

      result.fold(
        onSuccess: (_) => fail('expected a failure'),
        onFailure: (error) => expect(error, isA<ServerException>()),
      );
    });
  });

  group('ServersApi.sendPowerAction', () {
    test('sends POST to /api/client/servers/{server}/power with the right signal', () async {
      final adapter = FakeHttpClientAdapter((options) async => emptyResponseBody());
      final api = _buildApi(adapter);

      await api.sendPowerAction('d3aac109', ServerPowerAction.restart);

      expect(adapter.lastRequest?.method, 'POST');
      expect(adapter.lastRequest?.path, '/api/client/servers/d3aac109/power');
      expect(adapter.lastRequest?.data, {'signal': 'restart'});
    });

    for (final entry in {
      ServerPowerAction.start: 'start',
      ServerPowerAction.stop: 'stop',
      ServerPowerAction.restart: 'restart',
      ServerPowerAction.kill: 'kill',
    }.entries) {
      test('maps ${entry.key} to signal "${entry.value}"', () async {
        final adapter = FakeHttpClientAdapter((options) async => emptyResponseBody());
        final api = _buildApi(adapter);

        await api.sendPowerAction('d3aac109', entry.key);

        expect(adapter.lastRequest?.data, {'signal': entry.value});
      });
    }

    test('returns success on a 204 response', () async {
      final adapter = FakeHttpClientAdapter((options) async => emptyResponseBody());
      final api = _buildApi(adapter);

      final result = await api.sendPowerAction('d3aac109', ServerPowerAction.start);

      expect(result.isSuccess, isTrue);
    });

    test('maps an HTTP 401 response to UnauthorizedException', () async {
      final adapter = FakeHttpClientAdapter((options) async => jsonResponseBody({'errors': []}, statusCode: 401));
      final api = _buildApi(adapter);

      final result = await api.sendPowerAction('d3aac109', ServerPowerAction.start);

      result.fold(
        onSuccess: (_) => fail('expected a failure'),
        onFailure: (error) => expect(error, isA<UnauthorizedException>()),
      );
    });

    test('maps an HTTP 403 response to ForbiddenException', () async {
      final adapter = FakeHttpClientAdapter((options) async => jsonResponseBody({'errors': []}, statusCode: 403));
      final api = _buildApi(adapter);

      final result = await api.sendPowerAction('d3aac109', ServerPowerAction.kill);

      result.fold(
        onSuccess: (_) => fail('expected a failure'),
        onFailure: (error) => expect(error, isA<ForbiddenException>()),
      );
    });

    test('maps a connection error to NetworkException', () async {
      final adapter = FakeHttpClientAdapter(
        (options) async => throw DioException(requestOptions: options, type: DioExceptionType.connectionError),
      );
      final api = _buildApi(adapter);

      final result = await api.sendPowerAction('d3aac109', ServerPowerAction.stop);

      result.fold(
        onSuccess: (_) => fail('expected a failure'),
        onFailure: (error) => expect(error, isA<NetworkException>()),
      );
    });

    test('maps a send timeout to RequestTimeoutException', () async {
      final adapter = FakeHttpClientAdapter(
        (options) async => throw DioException(requestOptions: options, type: DioExceptionType.sendTimeout),
      );
      final api = _buildApi(adapter);

      final result = await api.sendPowerAction('d3aac109', ServerPowerAction.restart);

      result.fold(
        onSuccess: (_) => fail('expected a failure'),
        onFailure: (error) => expect(error, isA<RequestTimeoutException>()),
      );
    });
  });
}
