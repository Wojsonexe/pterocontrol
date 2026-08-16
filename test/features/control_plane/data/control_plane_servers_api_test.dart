import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pterodactyl_mobile/features/control_plane/data/control_plane_api_client.dart';
import 'package:pterodactyl_mobile/features/control_plane/data/control_plane_servers_api.dart';
import 'package:pterodactyl_mobile/features/control_plane/domain/control_plane_power_action.dart';

import '../../../support/fake_http_client_adapter.dart';

ControlPlaneServersApi _api(FutureOr<ResponseBody> Function(RequestOptions) handler) {
  final dio = Dio(BaseOptions(baseUrl: 'https://cp.example.com'))..httpClientAdapter = FakeHttpClientAdapter(handler);
  return ControlPlaneServersApi(ControlPlaneApiClient(dio: dio));
}

void main() {
  test('list() parses the raw Server[] rows from GET /servers', () async {
    final api = _api(
      (_) => jsonResponseBody([
        {
          'id': 'srv-1',
          'tenantId': 't-1',
          'instanceId': 'inst-1',
          'pterodactylId': 1,
          'pterodactylUuid': 'uuid-1',
          'identifier': 'd3aac109',
          'name': 'Survival',
          'nodeId': 1,
          'lastSyncedAt': '2026-08-16T12:00:00.000Z',
          'createdAt': '2026-08-16T10:00:00.000Z',
        },
      ]),
    );

    final result = await api.list();

    final servers = result.fold(onSuccess: (s) => s, onFailure: (_) => null);
    expect(servers, hasLength(1));
    expect(servers!.single.id, 'srv-1');
    expect(servers.single.instanceId, 'inst-1');
    expect(servers.single.identifier, 'd3aac109');
    expect(servers.single.name, 'Survival');
    expect(servers.single.nodeId, 1);
    expect(servers.single.lastSyncedAt, DateTime.parse('2026-08-16T12:00:00.000Z'));
  });

  test('getResources() parses PterodactylResourceUsageDto shape from GET /servers/:id/resources', () async {
    RequestOptions? captured;
    final api = _api((options) {
      captured = options;
      return jsonResponseBody({
        'currentState': 'running',
        'isSuspended': false,
        'cpuAbsolutePercent': 12.5,
        'memoryBytes': 268435456,
        'diskBytes': 1073741824,
        'networkRxBytes': 1000,
        'networkTxBytes': 2000,
        'uptimeMs': 3600000,
      });
    });

    final result = await api.getResources('srv-1');

    expect(captured!.path, '/servers/srv-1/resources');
    final usage = result.fold(onSuccess: (u) => u, onFailure: (_) => null);
    expect(usage!.currentState, 'running');
    expect(usage.isSuspended, false);
    expect(usage.cpuAbsolutePercent, 12.5);
    expect(usage.memoryBytes, 268435456);
  });

  test('sendPowerAction() POSTs {action} to /servers/:id/power', () async {
    RequestOptions? captured;
    final api = _api((options) {
      captured = options;
      return jsonResponseBody({'accepted': true}, statusCode: 202);
    });

    await api.sendPowerAction('srv-1', ControlPlanePowerAction.restart);

    expect(captured!.method, 'POST');
    expect(captured!.path, '/servers/srv-1/power');
    expect(captured!.data, {'action': 'restart'});
  });
}
