import { PterodactylApplicationApiClient } from '@pterocontrol/pterodactyl-sdk';
import { MessageEnvelope } from '@pterocontrol/rabbitmq';
import { SecretsService } from '@pterocontrol/secrets';
import { PermanentJobError } from '../errors/permanent-job-error';
import { PrismaService } from '../prisma/prisma.service';
import { ServerSyncHandler } from './server-sync.handler';

interface ServerUpsertArgs {
  where: { instanceId_pterodactylUuid: { instanceId: string; pterodactylUuid: string } };
  create: { tenantId: string; pterodactylUuid: string; name: string };
}

interface EventCreateArgs {
  data: { type: string; serverId?: string };
}

describe('ServerSyncHandler', () => {
  const prismaMock = {
    pterodactylInstance: { findFirst: jest.fn() },
    instanceCredential: { findUnique: jest.fn() },
    server: {
      findMany: jest.fn(),
      upsert: jest.fn<Promise<unknown>, [ServerUpsertArgs]>(),
    },
    event: { create: jest.fn<Promise<unknown>, [EventCreateArgs]>() },
  };
  const applicationApiMock = { listServers: jest.fn() };
  const secretsMock = { decrypt: jest.fn() };

  let handler: ServerSyncHandler;
  const tenantId = 't-1';
  const instanceId = 'inst-1';
  const instance = { id: instanceId, tenantId, baseUrl: 'https://panel.example.com' };

  function envelope(): MessageEnvelope {
    return {
      jobId: 'job-1',
      correlationId: 'job-1',
      tenantId,
      instanceId,
      createdAt: new Date().toISOString(),
      attempt: 0,
      payload: {},
    };
  }

  beforeEach(() => {
    jest.clearAllMocks();
    handler = new ServerSyncHandler(
      prismaMock as unknown as PrismaService,
      applicationApiMock as unknown as PterodactylApplicationApiClient,
      secretsMock as unknown as SecretsService,
    );
  });

  it('throws PermanentJobError when the instance does not belong to the tenant', async () => {
    prismaMock.pterodactylInstance.findFirst.mockResolvedValueOnce(null);

    await expect(handler.handle(envelope())).rejects.toThrow(PermanentJobError);
    expect(applicationApiMock.listServers).not.toHaveBeenCalled();
  });

  it('throws PermanentJobError when there is no stored Application API credential', async () => {
    prismaMock.pterodactylInstance.findFirst.mockResolvedValueOnce(instance);
    prismaMock.instanceCredential.findUnique.mockResolvedValueOnce(null);

    await expect(handler.handle(envelope())).rejects.toThrow(PermanentJobError);
  });

  it('lets a Pterodactyl-side failure propagate unwrapped (for the consumer to classify)', async () => {
    prismaMock.pterodactylInstance.findFirst.mockResolvedValueOnce(instance);
    prismaMock.instanceCredential.findUnique.mockResolvedValueOnce({
      ciphertext: Buffer.from('enc'),
    });
    secretsMock.decrypt.mockReturnValueOnce('decrypted-key');
    const upstreamError = new Error('network error');
    applicationApiMock.listServers.mockRejectedValueOnce(upstreamError);

    await expect(handler.handle(envelope())).rejects.toBe(upstreamError);
    expect(prismaMock.server.upsert).not.toHaveBeenCalled();
  });

  it('upserts each remote server keyed by (instanceId, pterodactylUuid) and emits server_created only for new ones', async () => {
    prismaMock.pterodactylInstance.findFirst.mockResolvedValueOnce(instance);
    prismaMock.instanceCredential.findUnique.mockResolvedValueOnce({
      ciphertext: Buffer.from('enc'),
    });
    secretsMock.decrypt.mockReturnValueOnce('decrypted-key');
    applicationApiMock.listServers.mockResolvedValueOnce([
      { id: 5, uuid: 'uuid-5', identifier: 'd5', name: 'Survival', node: 1 },
      { id: 6, uuid: 'uuid-6', identifier: 'd6', name: 'Creative', node: 1 },
    ]);
    prismaMock.server.findMany.mockResolvedValueOnce([{ pterodactylUuid: 'uuid-6' }]); // uuid-6 already known
    prismaMock.server.upsert
      .mockResolvedValueOnce({ id: 'srv-5' })
      .mockResolvedValueOnce({ id: 'srv-6' });
    prismaMock.event.create.mockResolvedValue({});

    await handler.handle(envelope());

    expect(applicationApiMock.listServers).toHaveBeenCalledWith(
      instance.baseUrl,
      'decrypted-key',
    );
    expect(prismaMock.server.upsert).toHaveBeenCalledTimes(2);
    const firstCallArgs = prismaMock.server.upsert.mock.calls[0][0];
    expect(firstCallArgs.where).toEqual({
      instanceId_pterodactylUuid: { instanceId, pterodactylUuid: 'uuid-5' },
    });
    expect(prismaMock.event.create).toHaveBeenCalledTimes(1);
    const eventArgs = prismaMock.event.create.mock.calls[0][0];
    expect(eventArgs.data).toEqual(
      expect.objectContaining({ type: 'server_created', serverId: 'srv-5' }),
    );
  });
});
