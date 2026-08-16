import {
  BadGatewayException,
  BadRequestException,
  NotFoundException,
  ServiceUnavailableException,
} from '@nestjs/common';
import {
  PterodactylAuthError,
  PterodactylClientApiClient,
} from '@pterocontrol/pterodactyl-sdk';
import {
  EXCHANGES,
  ROUTING_KEYS,
  RabbitMqPublisherService,
} from '@pterocontrol/rabbitmq';
import { SecretsService } from '@pterocontrol/secrets';
import { AuditService } from '../audit/audit.service';
import { InstancesService } from '../instances/instances.service';
import { PrismaService } from '../prisma/prisma.service';
import { ServersService } from './servers.service';

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
      findMany: jest.fn(),
      findFirst: jest.fn(),
    },
    resourceSnapshot: {
      create: jest.fn(),
      findMany: jest.fn(),
    },
  };
  const instancesServiceMock = { findOneForTenant: jest.fn() };
  const secretsMock = { decrypt: jest.fn() };
  const clientApiMock = { getResourceUsage: jest.fn(), sendPowerAction: jest.fn() };
  const auditServiceMock = { record: jest.fn<Promise<void>, [AuditRecordArgs]>() };
  const publisherMock = { publish: jest.fn() };

  let service: ServersService;
  const tenantId = 't-1';
  const instance = { id: 'inst-1', tenantId, baseUrl: 'https://panel.example.com' };

  beforeEach(() => {
    jest.clearAllMocks();
    service = new ServersService(
      prismaMock as unknown as PrismaService,
      instancesServiceMock as unknown as InstancesService,
      secretsMock as unknown as SecretsService,
      clientApiMock as unknown as PterodactylClientApiClient,
      auditServiceMock as unknown as AuditService,
      publisherMock as unknown as RabbitMqPublisherService,
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
      expect(publisherMock.publish).not.toHaveBeenCalled();
    });

    it('publishes a federation.server.sync job instead of calling Pterodactyl inline', async () => {
      instancesServiceMock.findOneForTenant.mockResolvedValueOnce(instance);

      const result = await service.syncInstance(tenantId, 'inst-1');

      expect(result.status).toBe('queued');
      expect(typeof result.jobId).toBe('string');
      expect(publisherMock.publish).toHaveBeenCalledWith(
        EXCHANGES.FEDERATION_COMMANDS,
        ROUTING_KEYS.SERVER_SYNC,
        expect.objectContaining({
          jobId: result.jobId,
          tenantId,
          instanceId: 'inst-1',
        }),
      );
    });

    it('returns a controlled 503 instead of crashing when RabbitMQ is down', async () => {
      instancesServiceMock.findOneForTenant.mockResolvedValueOnce(instance);
      publisherMock.publish.mockImplementationOnce(() => {
        throw new Error('RabbitMQ channel is not available (connection down)');
      });

      await expect(service.syncInstance(tenantId, 'inst-1')).rejects.toThrow(
        ServiceUnavailableException,
      );
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

    const fullUsage = {
      currentState: 'running',
      isSuspended: false,
      cpuAbsolutePercent: 12.5,
      memoryBytes: 2147483648,
      diskBytes: 8589934592,
      networkRxBytes: 1024,
      networkTxBytes: 2048,
      uptimeMs: 3600000,
    };

    it('fetches resources using the server identifier, not the internal global id', async () => {
      prismaMock.server.findFirst.mockResolvedValueOnce(server);
      instancesServiceMock.findOneForTenant.mockResolvedValueOnce(instance);
      prismaMock.instanceCredential.findUnique.mockResolvedValueOnce({
        ciphertext: Buffer.from('enc'),
      });
      secretsMock.decrypt.mockReturnValueOnce('client-key');
      clientApiMock.getResourceUsage.mockResolvedValueOnce(fullUsage);
      prismaMock.resourceSnapshot.create.mockResolvedValueOnce({});

      await service.getResources(tenantId, 'srv-1');

      expect(clientApiMock.getResourceUsage).toHaveBeenCalledWith(
        instance.baseUrl,
        'client-key',
        'd3aac109',
      );
    });

    it('records a ResourceSnapshot on every successful read', async () => {
      prismaMock.server.findFirst.mockResolvedValueOnce(server);
      instancesServiceMock.findOneForTenant.mockResolvedValueOnce(instance);
      prismaMock.instanceCredential.findUnique.mockResolvedValueOnce({
        ciphertext: Buffer.from('enc'),
      });
      secretsMock.decrypt.mockReturnValueOnce('client-key');
      clientApiMock.getResourceUsage.mockResolvedValueOnce(fullUsage);
      prismaMock.resourceSnapshot.create.mockResolvedValueOnce({});

      await service.getResources(tenantId, 'srv-1');

      expect(prismaMock.resourceSnapshot.create).toHaveBeenCalledWith({
        data: {
          tenantId,
          serverId: 'srv-1',
          cpuAbsolutePercent: 12.5,
          memoryBytes: BigInt(2147483648),
          diskBytes: BigInt(8589934592),
          networkRxBytes: BigInt(1024),
          networkTxBytes: BigInt(2048),
          uptimeMs: BigInt(3600000),
        },
      });
    });

    it('maps a Pterodactyl-side failure to BadGatewayException, not a raw 500, and records no snapshot', async () => {
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
      expect(prismaMock.resourceSnapshot.create).not.toHaveBeenCalled();
    });
  });

  describe('getResourceHistory', () => {
    it('checks tenant ownership before querying snapshots', async () => {
      prismaMock.server.findFirst.mockResolvedValueOnce(null);

      await expect(
        service.getResourceHistory('other-tenant', 'srv-1'),
      ).rejects.toThrow(NotFoundException);
      expect(prismaMock.resourceSnapshot.findMany).not.toHaveBeenCalled();
    });

    it('caps the limit at 500 regardless of what is requested', async () => {
      prismaMock.server.findFirst.mockResolvedValueOnce({ id: 'srv-1', tenantId });
      prismaMock.resourceSnapshot.findMany.mockResolvedValueOnce([]);

      await service.getResourceHistory(tenantId, 'srv-1', 10000);

      expect(prismaMock.resourceSnapshot.findMany).toHaveBeenCalledWith(
        expect.objectContaining({ take: 500 }),
      );
    });

    it('converts every BigInt column to a string (regression: raw BigInt crashes JSON.stringify)', async () => {
      prismaMock.server.findFirst.mockResolvedValueOnce({ id: 'srv-1', tenantId });
      prismaMock.resourceSnapshot.findMany.mockResolvedValueOnce([
        {
          id: 'snap-1',
          serverId: 'srv-1',
          observedAt: new Date('2026-01-01T00:00:00Z'),
          cpuAbsolutePercent: 12.5,
          memoryBytes: BigInt(2147483648),
          diskBytes: BigInt(8589934592),
          networkRxBytes: BigInt(1024),
          networkTxBytes: BigInt(2048),
          uptimeMs: BigInt(3600000),
        },
      ]);

      const result = await service.getResourceHistory(tenantId, 'srv-1');

      expect(result[0].memoryBytes).toBe('2147483648');
      expect(result[0].diskBytes).toBe('8589934592');
      expect(typeof result[0].memoryBytes).toBe('string');
      // The real regression: this must not throw.
      expect(() => JSON.stringify(result)).not.toThrow();
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
