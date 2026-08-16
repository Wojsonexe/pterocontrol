import { BadGatewayException, BadRequestException, NotFoundException } from '@nestjs/common';
import { AuditService } from '../audit/audit.service';
import { InstancesService } from '../instances/instances.service';
import { PterodactylApplicationApiClient } from '../pterodactyl/pterodactyl-application-api.client';
import { PterodactylClientApiClient } from '../pterodactyl/pterodactyl-client-api.client';
import { PterodactylAuthError, PterodactylNotFoundError } from '../pterodactyl/pterodactyl-http.client';
import { PrismaService } from '../prisma/prisma.service';
import { SecretsService } from '../secrets/secrets.service';
import { ServersService } from './servers.service';

interface ServerUpsertArgs {
  where: { instanceId_pterodactylUuid: { instanceId: string; pterodactylUuid: string } };
  create: { tenantId: string; pterodactylUuid: string; name: string };
}

interface AuditRecordArgs {
  tenantId: string;
  actorId?: string;
  action: string;
  targetType: string;
  targetId?: string;
  result: string;
  metadata?: unknown;
}

describe('ServersService', () => {
  const prismaMock = {
    instanceCredential: { findUnique: jest.fn() },
    server: {
      upsert: jest.fn<Promise<unknown>, [ServerUpsertArgs]>(),
      findMany: jest.fn(),
      findFirst: jest.fn(),
    },
  };
  const instancesServiceMock = { findOneForTenant: jest.fn() };
  const secretsMock = { decrypt: jest.fn() };
  const applicationApiMock = { listServers: jest.fn() };
  const clientApiMock = { getResourceUsage: jest.fn(), sendPowerAction: jest.fn() };
  const auditServiceMock = { record: jest.fn<Promise<void>, [AuditRecordArgs]>() };

  let service: ServersService;
  const tenantId = 't-1';
  const instance = { id: 'inst-1', tenantId, baseUrl: 'https://panel.example.com' };

  beforeEach(() => {
    jest.clearAllMocks();
    service = new ServersService(
      prismaMock as unknown as PrismaService,
      instancesServiceMock as unknown as InstancesService,
      secretsMock as unknown as SecretsService,
      applicationApiMock as unknown as PterodactylApplicationApiClient,
      clientApiMock as unknown as PterodactylClientApiClient,
      auditServiceMock as unknown as AuditService,
    );
  });

  describe('syncInstance', () => {
    it('rejects with 404 when the instance is not owned by the tenant (delegates to InstancesService)', async () => {
      instancesServiceMock.findOneForTenant.mockRejectedValueOnce(
        new NotFoundException('Instance not found'),
      );

      await expect(service.syncInstance(tenantId, 'inst-1')).rejects.toThrow(
        NotFoundException,
      );
      expect(applicationApiMock.listServers).not.toHaveBeenCalled();
    });

    it('rejects when the instance has no stored Application API credential', async () => {
      instancesServiceMock.findOneForTenant.mockResolvedValueOnce(instance);
      prismaMock.instanceCredential.findUnique.mockResolvedValueOnce(null);

      // BadRequestException, not NotFoundException: this is a
      // configuration problem ("you never gave this instance an
      // Application API key"), the same exception type getResources()/
      // sendPowerAction() use for their own missing-credential case
      // below - one shared getCredential() helper, one consistent status.
      await expect(service.syncInstance(tenantId, 'inst-1')).rejects.toThrow(
        BadRequestException,
      );
    });

    it('maps a Pterodactyl-side failure to a clean BadGatewayException, not a raw 500', async () => {
      instancesServiceMock.findOneForTenant.mockResolvedValueOnce(instance);
      prismaMock.instanceCredential.findUnique.mockResolvedValueOnce({
        ciphertext: Buffer.from('enc'),
      });
      secretsMock.decrypt.mockReturnValueOnce('decrypted-key');
      applicationApiMock.listServers.mockRejectedValueOnce(
        new PterodactylNotFoundError('Endpoint not found on Pterodactyl instance'),
      );

      await expect(service.syncInstance(tenantId, 'inst-1')).rejects.toThrow(
        BadGatewayException,
      );
      expect(prismaMock.server.upsert).not.toHaveBeenCalled();
    });

    it('upserts each remote server keyed by (instanceId, pterodactylUuid), never by the bare numeric id', async () => {
      instancesServiceMock.findOneForTenant.mockResolvedValueOnce(instance);
      prismaMock.instanceCredential.findUnique.mockResolvedValueOnce({
        ciphertext: Buffer.from('enc'),
      });
      secretsMock.decrypt.mockReturnValueOnce('decrypted-key');
      applicationApiMock.listServers.mockResolvedValueOnce([
        { id: 5, uuid: 'uuid-5', identifier: 'd5', name: 'Survival', node: 1 },
        { id: 6, uuid: 'uuid-6', identifier: 'd6', name: 'Creative', node: 1 },
      ]);
      prismaMock.server.upsert.mockResolvedValue({});

      const result = await service.syncInstance(tenantId, 'inst-1');

      expect(applicationApiMock.listServers).toHaveBeenCalledWith(
        instance.baseUrl,
        'decrypted-key',
      );
      expect(prismaMock.server.upsert).toHaveBeenCalledTimes(2);
      const firstCallArgs = prismaMock.server.upsert.mock.calls[0][0];
      expect(firstCallArgs.where).toEqual({
        instanceId_pterodactylUuid: { instanceId: 'inst-1', pterodactylUuid: 'uuid-5' },
      });
      expect(firstCallArgs.create.tenantId).toBe(tenantId);
      expect(firstCallArgs.create.pterodactylUuid).toBe('uuid-5');
      expect(firstCallArgs.create.name).toBe('Survival');
      expect(result).toEqual({ synced: 2 });
    });
  });

  describe('tenant isolation', () => {
    it('findAllForTenant always scopes by tenantId', async () => {
      prismaMock.server.findMany.mockResolvedValueOnce([]);

      await service.findAllForTenant(tenantId, {});

      expect(prismaMock.server.findMany).toHaveBeenCalledWith(
        expect.objectContaining({ where: { tenantId } }),
      );
    });

    it('applies instanceId and q filters on top of the tenant scope', async () => {
      prismaMock.server.findMany.mockResolvedValueOnce([]);

      await service.findAllForTenant(tenantId, { instanceId: 'inst-1', q: 'surv' });

      expect(prismaMock.server.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: {
            tenantId,
            instanceId: 'inst-1',
            name: { contains: 'surv', mode: 'insensitive' },
          },
        }),
      );
    });

    it('findOneForTenant returns 404 for a server belonging to another tenant', async () => {
      prismaMock.server.findFirst.mockResolvedValueOnce(null);

      await expect(
        service.findOneForTenant('other-tenant', 'srv-1'),
      ).rejects.toThrow(NotFoundException);
    });
  });

  describe('getResources', () => {
    const server = { id: 'srv-1', tenantId, instanceId: 'inst-1', identifier: 'd3aac109' };

    it('rejects with a clear error when no Client API key is configured', async () => {
      prismaMock.server.findFirst.mockResolvedValueOnce(server);
      instancesServiceMock.findOneForTenant.mockResolvedValueOnce(instance);
      prismaMock.instanceCredential.findUnique.mockResolvedValueOnce(null);

      await expect(service.getResources(tenantId, 'srv-1')).rejects.toThrow(
        BadRequestException,
      );
      expect(clientApiMock.getResourceUsage).not.toHaveBeenCalled();
    });

    it('fetches resources using the server identifier, not the internal global id', async () => {
      prismaMock.server.findFirst.mockResolvedValueOnce(server);
      instancesServiceMock.findOneForTenant.mockResolvedValueOnce(instance);
      prismaMock.instanceCredential.findUnique.mockResolvedValueOnce({
        ciphertext: Buffer.from('enc'),
      });
      secretsMock.decrypt.mockReturnValueOnce('client-key');
      clientApiMock.getResourceUsage.mockResolvedValueOnce({ currentState: 'running' });

      await service.getResources(tenantId, 'srv-1');

      expect(clientApiMock.getResourceUsage).toHaveBeenCalledWith(
        instance.baseUrl,
        'client-key',
        'd3aac109',
      );
    });

    it('maps a Pterodactyl-side failure to BadGatewayException, not a raw 500', async () => {
      prismaMock.server.findFirst.mockResolvedValueOnce(server);
      instancesServiceMock.findOneForTenant.mockResolvedValueOnce(instance);
      prismaMock.instanceCredential.findUnique.mockResolvedValueOnce({
        ciphertext: Buffer.from('enc'),
      });
      secretsMock.decrypt.mockReturnValueOnce('client-key');
      clientApiMock.getResourceUsage.mockRejectedValueOnce(
        new PterodactylAuthError('bad key'),
      );

      await expect(service.getResources(tenantId, 'srv-1')).rejects.toThrow(
        BadGatewayException,
      );
    });
  });

  describe('sendPowerAction', () => {
    const server = { id: 'srv-1', tenantId, instanceId: 'inst-1', identifier: 'd3aac109' };

    it('records a success audit entry when the power action succeeds', async () => {
      prismaMock.server.findFirst.mockResolvedValueOnce(server);
      instancesServiceMock.findOneForTenant.mockResolvedValueOnce(instance);
      prismaMock.instanceCredential.findUnique.mockResolvedValueOnce({
        ciphertext: Buffer.from('enc'),
      });
      secretsMock.decrypt.mockReturnValueOnce('client-key');
      clientApiMock.sendPowerAction.mockResolvedValueOnce(undefined);

      await service.sendPowerAction(tenantId, 'actor-1', 'srv-1', 'restart');

      expect(clientApiMock.sendPowerAction).toHaveBeenCalledWith(
        instance.baseUrl,
        'client-key',
        'd3aac109',
        'restart',
      );
      const auditArgs = auditServiceMock.record.mock.calls[0][0];
      expect(auditArgs).toEqual({
        tenantId,
        actorId: 'actor-1',
        action: 'power.restart',
        targetType: 'server',
        targetId: 'srv-1',
        result: 'success',
      });
    });

    it('records a failure audit entry AND still throws when the power action fails', async () => {
      prismaMock.server.findFirst.mockResolvedValueOnce(server);
      instancesServiceMock.findOneForTenant.mockResolvedValueOnce(instance);
      prismaMock.instanceCredential.findUnique.mockResolvedValueOnce({
        ciphertext: Buffer.from('enc'),
      });
      secretsMock.decrypt.mockReturnValueOnce('client-key');
      clientApiMock.sendPowerAction.mockRejectedValueOnce(
        new PterodactylAuthError('bad key'),
      );

      await expect(
        service.sendPowerAction(tenantId, 'actor-1', 'srv-1', 'kill'),
      ).rejects.toThrow(BadGatewayException);

      const auditArgs = auditServiceMock.record.mock.calls[0][0];
      expect(auditArgs.result).toBe('error');
      expect(auditArgs.action).toBe('power.kill');
    });

    it('never calls the Pterodactyl API at all for a server in another tenant (404 first)', async () => {
      prismaMock.server.findFirst.mockResolvedValueOnce(null);

      await expect(
        service.sendPowerAction('other-tenant', 'actor-1', 'srv-1', 'start'),
      ).rejects.toThrow(NotFoundException);
      expect(clientApiMock.sendPowerAction).not.toHaveBeenCalled();
      expect(auditServiceMock.record).not.toHaveBeenCalled();
    });
  });
});
