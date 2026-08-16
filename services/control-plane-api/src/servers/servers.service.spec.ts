import { BadGatewayException, NotFoundException } from '@nestjs/common';
import { InstancesService } from '../instances/instances.service';
import { PterodactylApplicationApiClient } from '../pterodactyl/pterodactyl-application-api.client';
import { PterodactylNotFoundError } from '../pterodactyl/pterodactyl-http.client';
import { PrismaService } from '../prisma/prisma.service';
import { SecretsService } from '../secrets/secrets.service';
import { ServersService } from './servers.service';

interface ServerUpsertArgs {
  where: { instanceId_pterodactylUuid: { instanceId: string; pterodactylUuid: string } };
  create: { tenantId: string; pterodactylUuid: string; name: string };
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

      await expect(service.syncInstance(tenantId, 'inst-1')).rejects.toThrow(
        NotFoundException,
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
});
