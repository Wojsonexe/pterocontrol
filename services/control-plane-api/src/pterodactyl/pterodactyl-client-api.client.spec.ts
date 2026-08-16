import { PterodactylClientApiClient } from './pterodactyl-client-api.client';
import { PterodactylHttpClient } from './pterodactyl-http.client';

describe('PterodactylClientApiClient', () => {
  const httpMock = { get: jest.fn(), post: jest.fn() };
  let client: PterodactylClientApiClient;

  beforeEach(() => {
    httpMock.get.mockReset();
    httpMock.post.mockReset();
    client = new PterodactylClientApiClient(
      httpMock as unknown as PterodactylHttpClient,
    );
  });

  describe('getResourceUsage', () => {
    it('parses the real Pterodactyl resources envelope into a typed DTO', async () => {
      httpMock.get.mockResolvedValueOnce({
        attributes: {
          current_state: 'running',
          is_suspended: false,
          resources: {
            memory_bytes: 2147483648,
            cpu_absolute: 34.2,
            disk_bytes: 8589934592,
            network_rx_bytes: 12400,
            network_tx_bytes: 3100,
            uptime: 3600000,
          },
        },
      });

      const result = await client.getResourceUsage(
        'https://panel.example.com',
        'key',
        'd3aac109',
      );

      expect(result).toEqual({
        currentState: 'running',
        isSuspended: false,
        cpuAbsolutePercent: 34.2,
        memoryBytes: 2147483648,
        diskBytes: 8589934592,
        networkRxBytes: 12400,
        networkTxBytes: 3100,
        uptimeMs: 3600000,
      });
      expect(httpMock.get).toHaveBeenCalledWith(
        'https://panel.example.com',
        '/api/client/servers/d3aac109/resources',
        'key',
      );
    });

    it('rejects a malformed response instead of returning garbage', async () => {
      httpMock.get.mockResolvedValueOnce({ not: 'the expected shape' });

      await expect(
        client.getResourceUsage('https://panel.example.com', 'key', 'd3aac109'),
      ).rejects.toThrow(/envelope/);
    });
  });

  describe('sendPowerAction', () => {
    it.each(['start', 'stop', 'restart', 'kill'] as const)(
      'sends {signal: "%s"} to the power endpoint',
      async (signal) => {
        httpMock.post.mockResolvedValueOnce(undefined);

        await client.sendPowerAction('https://panel.example.com', 'key', 'd3aac109', signal);

        expect(httpMock.post).toHaveBeenCalledWith(
          'https://panel.example.com',
          '/api/client/servers/d3aac109/power',
          'key',
          { signal },
        );
      },
    );

    it('propagates errors from the underlying HTTP client unchanged', async () => {
      httpMock.post.mockRejectedValueOnce(new Error('401'));

      await expect(
        client.sendPowerAction('https://panel.example.com', 'key', 'd3aac109', 'start'),
      ).rejects.toThrow('401');
    });
  });
});
