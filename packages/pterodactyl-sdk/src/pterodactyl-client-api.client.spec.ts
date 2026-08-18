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

  describe('schedules', () => {
    const rawTask = {
      attributes: {
        id: 1,
        sequence_id: 1,
        action: 'command',
        payload: 'say hello',
        time_offset: 0,
        is_queued: false,
      },
    };
    const rawSchedule = {
      attributes: {
        id: 5,
        name: 'Nightly restart',
        cron: { day_of_week: '*', day_of_month: '*', month: '*', hour: '3', minute: '0' },
        is_active: true,
        is_processing: false,
        only_when_online: true,
        last_run_at: null,
        next_run_at: '2026-08-17T03:00:00+00:00',
        created_at: '2026-08-16T12:00:00+00:00',
        updated_at: '2026-08-16T12:00:00+00:00',
        relationships: { tasks: { data: [rawTask] } },
      },
    };

    it('listSchedules parses schedules with nested tasks', async () => {
      httpMock.get.mockResolvedValueOnce({ data: [rawSchedule] });

      const result = await client.listSchedules('https://panel.example.com', 'key', 'd3aac109');

      expect(result).toHaveLength(1);
      expect(result[0].name).toBe('Nightly restart');
      expect(result[0].tasks).toEqual([
        { id: 1, sequenceId: 1, action: 'command', payload: 'say hello', timeOffset: 0, isQueued: false },
      ]);
      expect(httpMock.get).toHaveBeenCalledWith(
        'https://panel.example.com',
        '/api/client/servers/d3aac109/schedules',
        'key',
      );
    });

    it('createSchedule maps camelCase options to Pterodactyl snake_case fields', async () => {
      httpMock.post.mockResolvedValueOnce(rawSchedule);

      await client.createSchedule('https://panel.example.com', 'key', 'd3aac109', {
        name: 'Nightly restart',
        minute: '0',
        hour: '3',
        dayOfMonth: '*',
        month: '*',
        dayOfWeek: '*',
      });

      expect(httpMock.post).toHaveBeenCalledWith(
        'https://panel.example.com',
        '/api/client/servers/d3aac109/schedules',
        'key',
        {
          name: 'Nightly restart',
          minute: '0',
          hour: '3',
          day_of_month: '*',
          month: '*',
          day_of_week: '*',
          is_active: true,
          only_when_online: false,
        },
      );
    });

    it('deleteSchedule sends a DELETE to the schedule endpoint', async () => {
      httpMock.delete.mockResolvedValueOnce(undefined);

      await client.deleteSchedule('https://panel.example.com', 'key', 'd3aac109', 5);

      expect(httpMock.delete).toHaveBeenCalledWith(
        'https://panel.example.com',
        '/api/client/servers/d3aac109/schedules/5',
        'key',
      );
    });

    it('createScheduleTask sends the task payload and parses the response', async () => {
      httpMock.post.mockResolvedValueOnce(rawTask);

      const result = await client.createScheduleTask(
        'https://panel.example.com',
        'key',
        'd3aac109',
        5,
        { action: 'command', payload: 'say hello', timeOffset: 0 },
      );

      expect(result.action).toBe('command');
      expect(httpMock.post).toHaveBeenCalledWith(
        'https://panel.example.com',
        '/api/client/servers/d3aac109/schedules/5/tasks',
        'key',
        { action: 'command', payload: 'say hello', time_offset: 0 },
      );
    });
  });

  describe('allocations', () => {
    const rawAllocation = {
      attributes: { id: 1, ip: '10.0.0.1', ip_alias: null, port: 25565, notes: null, is_default: true },
    };

    it('listAllocations parses the envelope', async () => {
      httpMock.get.mockResolvedValueOnce({ data: [rawAllocation] });

      const result = await client.listAllocations('https://panel.example.com', 'key', 'd3aac109');

      expect(result).toEqual([
        { id: 1, ip: '10.0.0.1', ipAlias: null, port: 25565, notes: null, isDefault: true },
      ]);
    });

    it('createAllocation sends no body', async () => {
      httpMock.post.mockResolvedValueOnce(rawAllocation);

      await client.createAllocation('https://panel.example.com', 'key', 'd3aac109');

      expect(httpMock.post).toHaveBeenCalledWith(
        'https://panel.example.com',
        '/api/client/servers/d3aac109/network/allocations',
        'key',
        undefined,
      );
    });

    it('setAllocationNotes sends {notes}', async () => {
      httpMock.post.mockResolvedValueOnce({
        attributes: { ...rawAllocation.attributes, notes: 'main lobby' },
      });

      const result = await client.setAllocationNotes(
        'https://panel.example.com',
        'key',
        'd3aac109',
        1,
        'main lobby',
      );

      expect(result.notes).toBe('main lobby');
      expect(httpMock.post).toHaveBeenCalledWith(
        'https://panel.example.com',
        '/api/client/servers/d3aac109/network/allocations/1',
        'key',
        { notes: 'main lobby' },
      );
    });

    it('deleteAllocation sends a DELETE', async () => {
      httpMock.delete.mockResolvedValueOnce(undefined);

      await client.deleteAllocation('https://panel.example.com', 'key', 'd3aac109', 1);

      expect(httpMock.delete).toHaveBeenCalledWith(
        'https://panel.example.com',
        '/api/client/servers/d3aac109/network/allocations/1',
        'key',
      );
    });
  });

  describe('server databases', () => {
    const rawDatabase = {
      attributes: {
        id: 'db-1',
        host: { address: '10.0.0.5', port: 3306 },
        name: 's1_survival',
        username: 's1_survival',
        connections_from: '%',
        max_connections: 0,
        relationships: { password: { attributes: { password: 'secret123' } } },
      },
    };

    it('listServerDatabases parses the envelope including the nested password', async () => {
      httpMock.get.mockResolvedValueOnce({ data: [rawDatabase] });

      const result = await client.listServerDatabases(
        'https://panel.example.com',
        'key',
        'd3aac109',
      );

      expect(result).toEqual([
        {
          id: 'db-1',
          host: '10.0.0.5',
          port: 3306,
          name: 's1_survival',
          username: 's1_survival',
          connectionsFrom: '%',
          maxConnections: 0,
          password: 'secret123',
        },
      ]);
    });

    it('createServerDatabase defaults remote to "%"', async () => {
      httpMock.post.mockResolvedValueOnce(rawDatabase);

      await client.createServerDatabase(
        'https://panel.example.com',
        'key',
        'd3aac109',
        's1_survival',
      );

      expect(httpMock.post).toHaveBeenCalledWith(
        'https://panel.example.com',
        '/api/client/servers/d3aac109/databases',
        'key',
        { database: 's1_survival', remote: '%' },
      );
    });

    it('rotateServerDatabasePassword posts to the rotate-password endpoint', async () => {
      httpMock.post.mockResolvedValueOnce(rawDatabase);

      await client.rotateServerDatabasePassword(
        'https://panel.example.com',
        'key',
        'd3aac109',
        'db-1',
      );

      expect(httpMock.post).toHaveBeenCalledWith(
        'https://panel.example.com',
        '/api/client/servers/d3aac109/databases/db-1/rotate-password',
        'key',
        undefined,
      );
    });

    it('deleteServerDatabase sends a DELETE', async () => {
      httpMock.delete.mockResolvedValueOnce(undefined);

      await client.deleteServerDatabase('https://panel.example.com', 'key', 'd3aac109', 'db-1');

      expect(httpMock.delete).toHaveBeenCalledWith(
        'https://panel.example.com',
        '/api/client/servers/d3aac109/databases/db-1',
        'key',
      );
    });
  });

  describe('listActivity', () => {
    it('parses the activity log envelope', async () => {
      httpMock.get.mockResolvedValueOnce({
        data: [
          {
            attributes: {
              id: 'act-1',
              batch: null,
              event: 'server:power.start',
              is_api: true,
              ip: '203.0.113.5',
              description: null,
              timestamp: '2026-08-16T12:00:00+00:00',
            },
          },
        ],
      });

      const result = await client.listActivity('https://panel.example.com', 'key', 'd3aac109');

      expect(result).toEqual([
        {
          id: 'act-1',
          batch: null,
          event: 'server:power.start',
          isApi: true,
          ip: '203.0.113.5',
          description: null,
          timestamp: '2026-08-16T12:00:00+00:00',
        },
      ]);
      expect(httpMock.get).toHaveBeenCalledWith(
        'https://panel.example.com',
        '/api/client/servers/d3aac109/activity',
        'key',
      );
    });

    it('rejects a malformed response instead of returning garbage', async () => {
      httpMock.get.mockResolvedValueOnce({ not: 'a list envelope' });

      await expect(
        client.listActivity('https://panel.example.com', 'key', 'd3aac109'),
      ).rejects.toThrow(/envelope/);
    });
  });
});
