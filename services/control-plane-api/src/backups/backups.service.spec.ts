import { BadGatewayException, BadRequestException, NotFoundException } from '@nestjs/common';
import { PterodactylAuthError, PterodactylClientApiClient } from '@pterocontrol/pterodactyl-sdk';
import { SecretsService } from '@pterocontrol/secrets';
import { AuditService } from '../audit/audit.service';
import { InstancesService } from '../instances/instances.service';
import { PrismaService } from '../prisma/prisma.service';
import { ServersService } from '../servers/servers.service';
import { BackupsService } from './backups.service';

describe('BackupsService', () => {
  const prismaMock = { instanceCredential: { findUnique: jest.fn() } };
  const instancesServiceMock = { findOneForTenant: jest.fn() };
  const serversServiceMock = { findOneForTenant: jest.fn() };
  const secretsMock = { decrypt: jest.fn() };
  const clientApiMock = {
    listBackups: jest.fn(),
    createBackup: jest.fn(),
    getBackup: jest.fn(),
    getBackupDownloadUrl: jest.fn(),
    deleteBackup: jest.fn(),
    restoreBackup: jest.fn(),
    toggleBackupLock: jest.fn(),
  };
  const auditServiceMock = {
    record: jest.fn<
      Promise<void>,
      [
        {
          tenantId: string;
          actorId: string;
          action: string;
          targetType: string;
          targetId: string;
          result: string;
          metadata?: Record<string, unknown>;
        },
      ]
    >(),
  };

  let service: BackupsService;
  const tenantId = 't-1';
  const actorId = 'actor-1';
  const server = { id: 'srv-1', tenantId, instanceId: 'inst-1', identifier: 'd3aac109' };
  const instance = { id: 'inst-1', tenantId, baseUrl: 'https://panel.example.com' };

  beforeEach(() => {
    jest.clearAllMocks();
    service = new BackupsService(
      prismaMock as unknown as PrismaService,
      instancesServiceMock as unknown as InstancesService,
      serversServiceMock as unknown as ServersService,
      secretsMock as unknown as SecretsService,
      clientApiMock as unknown as PterodactylClientApiClient,
      auditServiceMock as unknown as AuditService,
    );
    serversServiceMock.findOneForTenant.mockResolvedValue(server);
    instancesServiceMock.findOneForTenant.mockResolvedValue(instance);
    prismaMock.instanceCredential.findUnique.mockResolvedValue({
      ciphertext: Buffer.from('enc'),
    });
    secretsMock.decrypt.mockReturnValue('client-key');
  });

  describe('tenant isolation', () => {
    it('never calls Pterodactyl for a server in another tenant', async () => {
      serversServiceMock.findOneForTenant.mockRejectedValueOnce(
        new NotFoundException('Server not found'),
      );

      await expect(service.list('other-tenant', 'srv-1')).rejects.toThrow(NotFoundException);
      expect(clientApiMock.listBackups).not.toHaveBeenCalled();
    });
  });

  describe('list', () => {
    it('fetches backups using the server identifier, not the internal global id', async () => {
      clientApiMock.listBackups.mockResolvedValueOnce([]);

      await service.list(tenantId, 'srv-1');

      expect(clientApiMock.listBackups).toHaveBeenCalledWith(
        instance.baseUrl,
        'client-key',
        'd3aac109',
      );
    });

    it('rejects with a clear error when no Client API key is configured', async () => {
      prismaMock.instanceCredential.findUnique.mockResolvedValueOnce(null);

      await expect(service.list(tenantId, 'srv-1')).rejects.toThrow(BadRequestException);
      expect(clientApiMock.listBackups).not.toHaveBeenCalled();
    });

    it('maps a Pterodactyl-side failure to BadGatewayException, not a raw 500', async () => {
      clientApiMock.listBackups.mockRejectedValueOnce(new PterodactylAuthError('bad key'));

      await expect(service.list(tenantId, 'srv-1')).rejects.toThrow(BadGatewayException);
    });
  });

  describe('create', () => {
    it('records a success audit entry with the new backup uuid', async () => {
      clientApiMock.createBackup.mockResolvedValueOnce({ uuid: 'backup-1', isLocked: false });

      await service.create(tenantId, actorId, 'srv-1', { name: 'manual' });

      expect(clientApiMock.createBackup).toHaveBeenCalledWith(
        instance.baseUrl,
        'client-key',
        'd3aac109',
        { name: 'manual', ignored: undefined, isLocked: undefined },
      );
      const auditArgs = auditServiceMock.record.mock.calls[0][0];
      expect(auditArgs.action).toBe('backup.create');
      expect(auditArgs.result).toBe('success');
      expect(auditArgs.metadata?.backupUuid).toBe('backup-1');
    });

    it('records a failure audit entry AND still throws when creation fails', async () => {
      clientApiMock.createBackup.mockRejectedValueOnce(new PterodactylAuthError('bad key'));

      await expect(service.create(tenantId, actorId, 'srv-1', {})).rejects.toThrow(
        BadGatewayException,
      );

      const auditArgs = auditServiceMock.record.mock.calls[0][0];
      expect(auditArgs.result).toBe('error');
    });
  });

  describe('remove', () => {
    it('records a success audit entry on delete', async () => {
      clientApiMock.deleteBackup.mockResolvedValueOnce(undefined);

      await service.remove(tenantId, actorId, 'srv-1', 'backup-1');

      expect(clientApiMock.deleteBackup).toHaveBeenCalledWith(
        instance.baseUrl,
        'client-key',
        'd3aac109',
        'backup-1',
      );
      const auditArgs = auditServiceMock.record.mock.calls[0][0];
      expect(auditArgs.action).toBe('backup.delete');
    });
  });

  describe('restore', () => {
    it('passes truncate through to the Pterodactyl client', async () => {
      clientApiMock.restoreBackup.mockResolvedValueOnce(undefined);

      await service.restore(tenantId, actorId, 'srv-1', 'backup-1', true);

      expect(clientApiMock.restoreBackup).toHaveBeenCalledWith(
        instance.baseUrl,
        'client-key',
        'd3aac109',
        'backup-1',
        true,
      );
    });
  });

  describe('toggleLock', () => {
    it('returns the updated backup and records the new lock state in the audit entry', async () => {
      clientApiMock.toggleBackupLock.mockResolvedValueOnce({ uuid: 'backup-1', isLocked: true });

      const result = await service.toggleLock(tenantId, actorId, 'srv-1', 'backup-1');

      expect(result.isLocked).toBe(true);
      const auditArgs = auditServiceMock.record.mock.calls[0][0];
      expect(auditArgs.metadata?.isLocked).toBe(true);
    });
  });
});
