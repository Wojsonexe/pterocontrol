import { PterodactylClientApiClient } from '@pterocontrol/pterodactyl-sdk';
import { MessageEnvelope } from '@pterocontrol/rabbitmq';
import { SecretsService } from '@pterocontrol/secrets';
import { PermanentJobError } from '../errors/permanent-job-error';
import { PrismaService } from '../prisma/prisma.service';
import { ResourcesCollectHandler } from './resources-collect.handler';

describe('ResourcesCollectHandler', () => {
  const prismaMock = {
    server: { findFirst: jest.fn() },
    pterodactylInstance: { findUnique: jest.fn() },
    instanceCredential: { findUnique: jest.fn() },
    resourceSnapshot: { create: jest.fn() },
  };
  const clientApiMock = { getResourceUsage: jest.fn() };
  const secretsMock = { decrypt: jest.fn() };

  let handler: ResourcesCollectHandler;
  const tenantId = 't-1';
  const serverId = 'srv-1';
  const server = { id: serverId, tenantId, instanceId: 'inst-1', identifier: 'd3aac109' };
  const instance = { id: 'inst-1', tenantId, baseUrl: 'https://panel.example.com' };

  function envelope(): MessageEnvelope {
    return {
      jobId: 'job-1',
      correlationId: 'job-1',
      tenantId,
      instanceId: 'inst-1',
      serverId,
      createdAt: new Date().toISOString(),
      attempt: 0,
      payload: {},
    };
  }

  beforeEach(() => {
    jest.clearAllMocks();
    handler = new ResourcesCollectHandler(
      prismaMock as unknown as PrismaService,
      clientApiMock as unknown as PterodactylClientApiClient,
      secretsMock as unknown as SecretsService,
    );
  });

  it('throws PermanentJobError when the server does not belong to the tenant', async () => {
    prismaMock.server.findFirst.mockResolvedValueOnce(null);

    await expect(handler.handle(envelope())).rejects.toThrow(PermanentJobError);
  });

  it('throws PermanentJobError when there is no Client API credential configured', async () => {
    prismaMock.server.findFirst.mockResolvedValueOnce(server);
    prismaMock.pterodactylInstance.findUnique.mockResolvedValueOnce(instance);
    prismaMock.instanceCredential.findUnique.mockResolvedValueOnce(null);

    await expect(handler.handle(envelope())).rejects.toThrow(PermanentJobError);
    expect(clientApiMock.getResourceUsage).not.toHaveBeenCalled();
  });

  it('writes a ResourceSnapshot with every BigInt field correctly rounded and typed', async () => {
    prismaMock.server.findFirst.mockResolvedValueOnce(server);
    prismaMock.pterodactylInstance.findUnique.mockResolvedValueOnce(instance);
    prismaMock.instanceCredential.findUnique.mockResolvedValueOnce({
      ciphertext: Buffer.from('enc'),
    });
    secretsMock.decrypt.mockReturnValueOnce('client-key');
    clientApiMock.getResourceUsage.mockResolvedValueOnce({
      currentState: 'running',
      isSuspended: false,
      cpuAbsolutePercent: 12.5,
      memoryBytes: 2147483648,
      diskBytes: 8589934592,
      networkRxBytes: 1024,
      networkTxBytes: 2048,
      uptimeMs: 3600000,
    });
    prismaMock.resourceSnapshot.create.mockResolvedValueOnce({});

    await handler.handle(envelope());

    expect(clientApiMock.getResourceUsage).toHaveBeenCalledWith(
      instance.baseUrl,
      'client-key',
      'd3aac109',
    );
    expect(prismaMock.resourceSnapshot.create).toHaveBeenCalledWith({
      data: {
        tenantId,
        serverId,
        cpuAbsolutePercent: 12.5,
        memoryBytes: BigInt(2147483648),
        diskBytes: BigInt(8589934592),
        networkRxBytes: BigInt(1024),
        networkTxBytes: BigInt(2048),
        uptimeMs: BigInt(3600000),
      },
    });
  });

  it('lets a Pterodactyl-side failure propagate unwrapped (for the consumer to classify) and records no snapshot', async () => {
    prismaMock.server.findFirst.mockResolvedValueOnce(server);
    prismaMock.pterodactylInstance.findUnique.mockResolvedValueOnce(instance);
    prismaMock.instanceCredential.findUnique.mockResolvedValueOnce({
      ciphertext: Buffer.from('enc'),
    });
    secretsMock.decrypt.mockReturnValueOnce('client-key');
    const networkError = new Error('ECONNREFUSED');
    clientApiMock.getResourceUsage.mockRejectedValueOnce(networkError);

    await expect(handler.handle(envelope())).rejects.toBe(networkError);
    expect(prismaMock.resourceSnapshot.create).not.toHaveBeenCalled();
  });
});
