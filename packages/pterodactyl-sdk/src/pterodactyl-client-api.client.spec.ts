import { PterodactylClientApiClient } from './pterodactyl-client-api.client';
import { PterodactylHttpClient } from './pterodactyl-http.client';

describe('PterodactylClientApiClient', () => {
  const httpMock = { get: jest.fn(), post: jest.fn(), delete: jest.fn(), put: jest.fn() };
  let client: PterodactylClientApiClient;

  const rawBackup = {
    attributes: {
      uuid: 'backup-uuid-1',
      name: 'daily-backup',
      ignored_files: ['*.log'],
      sha256_hash: 'abc123',
      bytes: 104857600,
      is_successful: true,
      is_locked: false,
      created_at: '2026-08-16T12:00:00+00:00',
      completed_at: '2026-08-16T12:05:00+00:00',
    },
  };
  const dtoBackup = {
    uuid: 'backup-uuid-1',
    name: 'daily-backup',
    ignoredFiles: ['*.log'],
    sha256Hash: 'abc123',
    bytes: 104857600,
    isSuccessful: true,
    isLocked: false,
    createdAt: '2026-08-16T12:00:00+00:00',
    completedAt: '2026-08-16T12:05:00+00:00',
  };

  beforeEach(() => {
    httpMock.get.mockReset();
    httpMock.post.mockReset();
    httpMock.delete.mockReset();
    httpMock.put.mockReset();
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

  describe('listBackups', () => {
    it('parses the real Pterodactyl backups list envelope into typed DTOs', async () => {
      httpMock.get.mockResolvedValueOnce({ data: [rawBackup] });

      const result = await client.listBackups('https://panel.example.com', 'key', 'd3aac109');

      expect(result).toEqual([dtoBackup]);
      expect(httpMock.get).toHaveBeenCalledWith(
        'https://panel.example.com',
        '/api/client/servers/d3aac109/backups',
        'key',
      );
    });

    it('rejects a malformed response instead of returning garbage', async () => {
      httpMock.get.mockResolvedValueOnce({ not: 'a list envelope' });

      await expect(
        client.listBackups('https://panel.example.com', 'key', 'd3aac109'),
      ).rejects.toThrow(/envelope/);
    });
  });

  describe('createBackup', () => {
    it('sends only the provided optional fields', async () => {
      httpMock.post.mockResolvedValueOnce(rawBackup);

      const result = await client.createBackup('https://panel.example.com', 'key', 'd3aac109', {
        name: 'manual-backup',
        isLocked: true,
      });

      expect(result).toEqual(dtoBackup);
      expect(httpMock.post).toHaveBeenCalledWith(
        'https://panel.example.com',
        '/api/client/servers/d3aac109/backups',
        'key',
        { name: 'manual-backup', is_locked: true },
      );
    });

    it('sends an empty body when no options are given', async () => {
      httpMock.post.mockResolvedValueOnce(rawBackup);

      await client.createBackup('https://panel.example.com', 'key', 'd3aac109');

      expect(httpMock.post).toHaveBeenCalledWith(
        'https://panel.example.com',
        '/api/client/servers/d3aac109/backups',
        'key',
        {},
      );
    });
  });

  describe('getBackup', () => {
    it('fetches a single backup by uuid', async () => {
      httpMock.get.mockResolvedValueOnce(rawBackup);

      const result = await client.getBackup(
        'https://panel.example.com',
        'key',
        'd3aac109',
        'backup-uuid-1',
      );

      expect(result).toEqual(dtoBackup);
      expect(httpMock.get).toHaveBeenCalledWith(
        'https://panel.example.com',
        '/api/client/servers/d3aac109/backups/backup-uuid-1',
        'key',
      );
    });
  });

  describe('getBackupDownloadUrl', () => {
    it('extracts the signed url from the envelope', async () => {
      httpMock.get.mockResolvedValueOnce({
        attributes: { url: 'https://panel.example.com/download/signed-token' },
      });

      const url = await client.getBackupDownloadUrl(
        'https://panel.example.com',
        'key',
        'd3aac109',
        'backup-uuid-1',
      );

      expect(url).toBe('https://panel.example.com/download/signed-token');
      expect(httpMock.get).toHaveBeenCalledWith(
        'https://panel.example.com',
        '/api/client/servers/d3aac109/backups/backup-uuid-1/download',
        'key',
      );
    });

    it('rejects a malformed response instead of returning garbage', async () => {
      httpMock.get.mockResolvedValueOnce({ attributes: {} });

      await expect(
        client.getBackupDownloadUrl('https://panel.example.com', 'key', 'd3aac109', 'backup-uuid-1'),
      ).rejects.toThrow(/envelope/);
    });
  });

  describe('deleteBackup', () => {
    it('sends a DELETE to the backup endpoint', async () => {
      httpMock.delete.mockResolvedValueOnce(undefined);

      await client.deleteBackup('https://panel.example.com', 'key', 'd3aac109', 'backup-uuid-1');

      expect(httpMock.delete).toHaveBeenCalledWith(
        'https://panel.example.com',
        '/api/client/servers/d3aac109/backups/backup-uuid-1',
        'key',
      );
    });
  });

  describe('restoreBackup', () => {
    it('defaults truncate to false', async () => {
      httpMock.post.mockResolvedValueOnce(undefined);

      await client.restoreBackup('https://panel.example.com', 'key', 'd3aac109', 'backup-uuid-1');

      expect(httpMock.post).toHaveBeenCalledWith(
        'https://panel.example.com',
        '/api/client/servers/d3aac109/backups/backup-uuid-1/restore',
        'key',
        { truncate: false },
      );
    });

    it('sends truncate: true when requested', async () => {
      httpMock.post.mockResolvedValueOnce(undefined);

      await client.restoreBackup(
        'https://panel.example.com',
        'key',
        'd3aac109',
        'backup-uuid-1',
        true,
      );

      expect(httpMock.post).toHaveBeenCalledWith(
        'https://panel.example.com',
        '/api/client/servers/d3aac109/backups/backup-uuid-1/restore',
        'key',
        { truncate: true },
      );
    });
  });

  describe('toggleBackupLock', () => {
    it('posts with no body and returns the updated backup', async () => {
      httpMock.post.mockResolvedValueOnce({
        attributes: { ...rawBackup.attributes, is_locked: true },
      });

      const result = await client.toggleBackupLock(
        'https://panel.example.com',
        'key',
        'd3aac109',
        'backup-uuid-1',
      );

      expect(result.isLocked).toBe(true);
      expect(httpMock.post).toHaveBeenCalledWith(
        'https://panel.example.com',
        '/api/client/servers/d3aac109/backups/backup-uuid-1/lock',
        'key',
        undefined,
      );
    });
  });

  describe('getStartupVariables', () => {
    const rawVariable = {
      attributes: {
        name: 'Server Jar File',
        description: 'The jar file to run',
        env_variable: 'SERVER_JARFILE',
        default_value: 'server.jar',
        server_value: 'paper.jar',
        is_editable: true,
        rules: 'required|string|max:20',
      },
    };

    it('parses the real Pterodactyl startup envelope into typed DTOs', async () => {
      httpMock.get.mockResolvedValueOnce({ data: [rawVariable] });

      const result = await client.getStartupVariables(
        'https://panel.example.com',
        'key',
        'd3aac109',
      );

      expect(result).toEqual([
        {
          name: 'Server Jar File',
          description: 'The jar file to run',
          envVariable: 'SERVER_JARFILE',
          defaultValue: 'server.jar',
          serverValue: 'paper.jar',
          isEditable: true,
          rules: 'required|string|max:20',
        },
      ]);
      expect(httpMock.get).toHaveBeenCalledWith(
        'https://panel.example.com',
        '/api/client/servers/d3aac109/startup',
        'key',
      );
    });

    it('rejects a malformed response instead of returning garbage', async () => {
      httpMock.get.mockResolvedValueOnce({ not: 'a list envelope' });

      await expect(
        client.getStartupVariables('https://panel.example.com', 'key', 'd3aac109'),
      ).rejects.toThrow(/envelope/);
    });
  });

  describe('updateStartupVariable', () => {
    it('sends a PUT with {key, value} and returns the updated variable', async () => {
      httpMock.put.mockResolvedValueOnce({
        attributes: {
          name: 'Server Jar File',
          description: 'The jar file to run',
          env_variable: 'SERVER_JARFILE',
          default_value: 'server.jar',
          server_value: 'paper-new.jar',
          is_editable: true,
          rules: 'required|string|max:20',
        },
      });

      const result = await client.updateStartupVariable(
        'https://panel.example.com',
        'key',
        'd3aac109',
        'SERVER_JARFILE',
        'paper-new.jar',
      );

      expect(result.serverValue).toBe('paper-new.jar');
      expect(httpMock.put).toHaveBeenCalledWith(
        'https://panel.example.com',
        '/api/client/servers/d3aac109/startup/variable',
        'key',
        { key: 'SERVER_JARFILE', value: 'paper-new.jar' },
      );
    });
  });
});
