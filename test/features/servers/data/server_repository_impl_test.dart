import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pterodactyl_mobile/core/error/app_exception.dart';
import 'package:pterodactyl_mobile/core/network/pterodactyl_api_client.dart';
import 'package:pterodactyl_mobile/features/servers/data/server_repository_impl.dart';
import 'package:pterodactyl_mobile/features/servers/data/servers_api.dart';
import 'package:pterodactyl_mobile/features/servers/domain/server.dart';
import 'package:pterodactyl_mobile/features/servers/domain/server_power_action.dart';
import 'package:pterodactyl_mobile/features/servers/domain/server_power_state.dart';

import '../../../support/fake_http_client_adapter.dart';

ServerRepositoryImpl _buildRepository(FakeHttpClientAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://panel.example.com'))..httpClientAdapter = adapter;
  return ServerRepositoryImpl(ServersApi(PterodactylApiClient(dio: dio)));
}

Map<String, dynamic> _serverAttributes({
  required String identifier,
  required String? description,
  required String? status,
  bool isTransferring = false,
}) {
  return {
    'identifier': identifier,
    'uuid': 'uuid-$identifier',
    'name': 'Server $identifier',
    'description': description,
    'node': 'Node 1',
    'status': status,
    'is_transferring': isTransferring,
    'limits': {'memory': 512, 'disk': 2048, 'cpu': 0},
  };
}

void main() {
  group('ServerRepositoryImpl.getServers', () {
    test('maps DTOs to domain Server objects, normalizing status and description', () async {
      final adapter = FakeHttpClientAdapter(
        (options) async => jsonResponseBody({
          'object': 'list',
          'data': [
            {
              'object': 'server',
              'attributes': _serverAttributes(identifier: 'a1', description: '', status: null),
            },
            {
              'object': 'server',
              'attributes': _serverAttributes(
                identifier: 'a2',
                description: 'A real description',
                status: 'suspended',
                isTransferring: true,
              ),
            },
            {
              'object': 'server',
              'attributes': _serverAttributes(identifier: 'a3', description: null, status: 'some_future_status'),
            },
          ],
          'meta': {
            'pagination': {'total': 3, 'count': 3, 'per_page': 50, 'current_page': 1, 'total_pages': 1},
          },
        }),
      );

      final repository = _buildRepository(adapter);
      final page = await repository.getServers();

      expect(page.servers, hasLength(3));

      final a1 = page.servers[0];
      expect(a1.description, isNull, reason: 'an empty description string should normalize to null');
      expect(a1.status, ServerAdministrativeStatus.active, reason: 'a null status means "active"');

      final a2 = page.servers[1];
      expect(a2.description, 'A real description');
      expect(a2.status, ServerAdministrativeStatus.suspended);
      expect(a2.isTransferring, isTrue);

      final a3 = page.servers[2];
      expect(
        a3.status,
        ServerAdministrativeStatus.unknown,
        reason: 'an unrecognized status string must not crash, only degrade gracefully',
      );
    });

    test('exposes pagination info from the response', () async {
      final adapter = FakeHttpClientAdapter(
        (options) async => jsonResponseBody({
          'object': 'list',
          'data': const [],
          'meta': {
            'pagination': {'total': 0, 'count': 0, 'per_page': 50, 'current_page': 2, 'total_pages': 5},
          },
        }),
      );

      final repository = _buildRepository(adapter);
      final page = await repository.getServers(page: 2);

      expect(page.page, 2);
      expect(page.totalPages, 5);
      expect(page.hasNextPage, isTrue);
    });

    test('throws the mapped AppException on an HTTP error instead of leaking DioException', () async {
      final adapter = FakeHttpClientAdapter(
        (options) async => jsonResponseBody({'errors': []}, statusCode: 500),
      );
      final repository = _buildRepository(adapter);

      await expectLater(repository.getServers(), throwsA(isA<ServerException>()));
    });

    test('throws UnauthorizedException on an HTTP 401', () async {
      final adapter = FakeHttpClientAdapter(
        (options) async => jsonResponseBody({'errors': []}, statusCode: 401),
      );
      final repository = _buildRepository(adapter);

      await expectLater(repository.getServers(), throwsA(isA<UnauthorizedException>()));
    });
  });

  group('ServerRepositoryImpl.getServer', () {
    test('maps a single-server response to a domain Server', () async {
      final adapter = FakeHttpClientAdapter(
        (options) async => jsonResponseBody({
          'object': 'server',
          'attributes': _serverAttributes(identifier: 'a1', description: 'desc', status: 'installing'),
        }),
      );
      final repository = _buildRepository(adapter);

      final server = await repository.getServer('a1');

      expect(adapter.lastRequest?.path, '/api/client/servers/a1');
      expect(server.identifier, 'a1');
      expect(server.status, ServerAdministrativeStatus.installing);
    });

    test('throws the mapped AppException on an HTTP error instead of leaking DioException', () async {
      final adapter = FakeHttpClientAdapter((options) async => jsonResponseBody({'errors': []}, statusCode: 404));
      final repository = _buildRepository(adapter);

      await expectLater(repository.getServer('missing'), throwsA(isA<NotFoundException>()));
    });
  });

  group('ServerRepositoryImpl.getResourceUsage', () {
    Map<String, dynamic> resourcesJson({String currentState = 'running'}) => {
          'object': 'stats',
          'attributes': {
            'current_state': currentState,
            'is_suspended': false,
            'resources': {
              'memory_bytes': 100,
              'cpu_absolute': 5.5,
              'disk_bytes': 200,
              'network_rx_bytes': 10,
              'network_tx_bytes': 20,
              'uptime': 60000,
            },
          },
        };

    for (final entry in {
      'offline': ServerPowerState.offline,
      'starting': ServerPowerState.starting,
      'running': ServerPowerState.running,
      'stopping': ServerPowerState.stopping,
      'some_future_state': ServerPowerState.unknown,
    }.entries) {
      test('maps current_state "${entry.key}" to ${entry.value}', () async {
        final adapter = FakeHttpClientAdapter(
          (options) async => jsonResponseBody(resourcesJson(currentState: entry.key)),
        );
        final repository = _buildRepository(adapter);

        final runtime = await repository.getResourceUsage('a1');

        expect(runtime.powerState, entry.value);
      });
    }

    test('maps resource fields and stamps observedAt', () async {
      final before = DateTime.now();
      final adapter = FakeHttpClientAdapter((options) async => jsonResponseBody(resourcesJson()));
      final repository = _buildRepository(adapter);

      final runtime = await repository.getResourceUsage('a1');

      expect(adapter.lastRequest?.path, '/api/client/servers/a1/resources');
      expect(runtime.cpuAbsolutePercent, 5.5);
      expect(runtime.memoryBytes, 100);
      expect(runtime.diskBytes, 200);
      expect(runtime.networkRxBytes, 10);
      expect(runtime.networkTxBytes, 20);
      expect(runtime.uptimeMs, 60000);
      expect(runtime.observedAt, isNotNull);
      expect(runtime.observedAt!.isBefore(before), isFalse);
    });

    test('throws the mapped AppException on an HTTP error instead of leaking DioException', () async {
      final adapter = FakeHttpClientAdapter((options) async => jsonResponseBody({'errors': []}, statusCode: 500));
      final repository = _buildRepository(adapter);

      await expectLater(repository.getResourceUsage('a1'), throwsA(isA<ServerException>()));
    });
  });

  group('ServerRepositoryImpl.sendPowerAction', () {
    test('completes without throwing on success', () async {
      final adapter = FakeHttpClientAdapter((options) async => emptyResponseBody());
      final repository = _buildRepository(adapter);

      await expectLater(repository.sendPowerAction('a1', ServerPowerAction.start), completes);

      expect(adapter.lastRequest?.path, '/api/client/servers/a1/power');
      expect(adapter.lastRequest?.data, {'signal': 'start'});
    });

    test('throws the mapped AppException on an HTTP error instead of leaking DioException', () async {
      final adapter = FakeHttpClientAdapter((options) async => jsonResponseBody({'errors': []}, statusCode: 403));
      final repository = _buildRepository(adapter);

      await expectLater(
        repository.sendPowerAction('a1', ServerPowerAction.kill),
        throwsA(isA<ForbiddenException>()),
      );
    });
  });
}
