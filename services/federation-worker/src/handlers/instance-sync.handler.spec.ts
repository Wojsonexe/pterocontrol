import { InstanceStatus } from '@prisma/client';
import {
  PterodactylApplicationApiClient,
  PterodactylAuthError,
  SsrfValidatorService,
} from '@pterocontrol/pterodactyl-sdk';
import { MessageEnvelope } from '@pterocontrol/rabbitmq';
import { SecretsService } from '@pterocontrol/secrets';
import { PermanentJobError } from '../errors/permanent-job-error';
import { PrismaService } from '../prisma/prisma.service';
import { InstanceSyncHandler } from './instance-sync.handler';

interface InstanceUpdateArgs {
  where: { id: string };
  data: { status: InstanceStatus; lastSyncedAt?: Date; lastError?: string | null };
}

interface EventCreateArgs {
  data: { type: string; payload: { from: InstanceStatus; to: InstanceStatus } };
}

describe('InstanceSyncHandler', () => {
  const prismaMock = {
    pterodactylInstance: {
      findFirst: jest.fn(),
      update: jest.fn<Promise<unknown>, [InstanceUpdateArgs]>(),
    },
    instanceCredential: { findUnique: jest.fn() },
    event: { create: jest.fn<Promise<unknown>, [EventCreateArgs]>() },
  };
  const ssrfMock = { assertSafeInstanceUrl: jest.fn() };
  const applicationApiMock = { testConnection: jest.fn() };
  const secretsMock = { decrypt: jest.fn() };

  let handler: InstanceSyncHandler;
  const tenantId = 't-1';
  const instanceId = 'inst-1';

  function envelope(overrides: Partial<MessageEnvelope> = {}): MessageEnvelope {
    return {
      jobId: 'job-1',
      correlationId: 'job-1',
      tenantId,
      instanceId,
      createdAt: new Date().toISOString(),
      attempt: 0,
      payload: {},
      ...overrides,
    };
  }

  beforeEach(() => {
    jest.clearAllMocks();
    handler = new InstanceSyncHandler(
      prismaMock as unknown as PrismaService,
      ssrfMock as unknown as SsrfValidatorService,
      applicationApiMock as unknown as PterodactylApplicationApiClient,
      secretsMock as unknown as SecretsService,
    );
  });

  it('throws PermanentJobError when the envelope is missing instanceId', async () => {
    await expect(
      handler.handle(envelope({ instanceId: undefined })),
    ).rejects.toThrow(PermanentJobError);
    expect(prismaMock.pterodactylInstance.findFirst).not.toHaveBeenCalled();
  });

  it('throws PermanentJobError when the instance does not belong to the tenant', async () => {
    prismaMock.pterodactylInstance.findFirst.mockResolvedValueOnce(null);

    await expect(handler.handle(envelope())).rejects.toThrow(PermanentJobError);
  });

  it('throws PermanentJobError when there is no stored Application API credential', async () => {
    prismaMock.pterodactylInstance.findFirst.mockResolvedValueOnce({
      id: instanceId,
      tenantId,
      baseUrl: 'https://panel.example.com',
      status: InstanceStatus.PENDING_SYNC,
    });
    prismaMock.instanceCredential.findUnique.mockResolvedValueOnce(null);

    await expect(handler.handle(envelope())).rejects.toThrow(PermanentJobError);
  });

  it('marks the instance ONLINE and emits instance_status_changed on a successful connectivity test', async () => {
    prismaMock.pterodactylInstance.findFirst.mockResolvedValueOnce({
      id: instanceId,
      tenantId,
      baseUrl: 'https://panel.example.com',
      status: InstanceStatus.PENDING_SYNC,
    });
    prismaMock.instanceCredential.findUnique.mockResolvedValueOnce({
      ciphertext: Buffer.from('enc'),
    });
    secretsMock.decrypt.mockReturnValueOnce('decrypted-key');
    ssrfMock.assertSafeInstanceUrl.mockResolvedValueOnce(undefined);
    applicationApiMock.testConnection.mockResolvedValueOnce(undefined);
    prismaMock.pterodactylInstance.update.mockResolvedValueOnce({});
    prismaMock.event.create.mockResolvedValueOnce({});

    await handler.handle(envelope());

    const updateArgs = prismaMock.pterodactylInstance.update.mock.calls[0][0];
    expect(updateArgs.where).toEqual({ id: instanceId });
    expect(updateArgs.data.status).toBe(InstanceStatus.ONLINE);
    expect(updateArgs.data.lastSyncedAt).toBeInstanceOf(Date);
    expect(updateArgs.data.lastError).toBeNull();
    const eventArgs = prismaMock.event.create.mock.calls[0][0];
    expect(eventArgs.data.type).toBe('instance_status_changed');
    expect(eventArgs.data.payload).toEqual({
      from: InstanceStatus.PENDING_SYNC,
      to: InstanceStatus.ONLINE,
    });
  });

  it('marks the instance UNREACHABLE, emits the event, then RETHROWS the original error for retry/DLQ classification', async () => {
    prismaMock.pterodactylInstance.findFirst.mockResolvedValueOnce({
      id: instanceId,
      tenantId,
      baseUrl: 'https://panel.example.com',
      status: InstanceStatus.ONLINE,
    });
    prismaMock.instanceCredential.findUnique.mockResolvedValueOnce({
      ciphertext: Buffer.from('enc'),
    });
    secretsMock.decrypt.mockReturnValueOnce('decrypted-key');
    ssrfMock.assertSafeInstanceUrl.mockResolvedValueOnce(undefined);
    const authError = new PterodactylAuthError('bad key');
    applicationApiMock.testConnection.mockRejectedValueOnce(authError);
    prismaMock.pterodactylInstance.update.mockResolvedValueOnce({});
    prismaMock.event.create.mockResolvedValueOnce({});

    await expect(handler.handle(envelope())).rejects.toBe(authError);

    expect(prismaMock.pterodactylInstance.update).toHaveBeenCalledWith({
      where: { id: instanceId },
      data: { status: InstanceStatus.UNREACHABLE, lastError: 'bad key' },
    });
    const eventArgs = prismaMock.event.create.mock.calls[0][0];
    expect(eventArgs.data.type).toBe('instance_status_changed');
    expect(eventArgs.data.payload).toEqual({
      from: InstanceStatus.ONLINE,
      to: InstanceStatus.UNREACHABLE,
    });
  });

  it('does not emit an event when the status does not actually change', async () => {
    prismaMock.pterodactylInstance.findFirst.mockResolvedValueOnce({
      id: instanceId,
      tenantId,
      baseUrl: 'https://panel.example.com',
      status: InstanceStatus.UNREACHABLE,
    });
    prismaMock.instanceCredential.findUnique.mockResolvedValueOnce({
      ciphertext: Buffer.from('enc'),
    });
    secretsMock.decrypt.mockReturnValueOnce('decrypted-key');
    ssrfMock.assertSafeInstanceUrl.mockResolvedValueOnce(undefined);
    const authError = new PterodactylAuthError('still bad');
    applicationApiMock.testConnection.mockRejectedValueOnce(authError);
    prismaMock.pterodactylInstance.update.mockResolvedValueOnce({});

    await expect(handler.handle(envelope())).rejects.toBe(authError);

    expect(prismaMock.event.create).not.toHaveBeenCalled();
  });
});
