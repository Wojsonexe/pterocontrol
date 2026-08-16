import type { ConsumeMessage } from 'amqplib';
import { PterodactylAuthError } from '@pterocontrol/pterodactyl-sdk';
import {
  EXCHANGES,
  MAX_RETRY_ATTEMPTS,
  MessageEnvelope,
  QUEUES,
  RabbitMqConnectionService,
  RabbitMqPublisherService,
  ROUTING_KEYS,
} from '@pterocontrol/rabbitmq';
import { InstanceSyncHandler } from '../handlers/instance-sync.handler';
import { ResourcesCollectHandler } from '../handlers/resources-collect.handler';
import { ServerSyncHandler } from '../handlers/server-sync.handler';
import { IdempotencyService } from '../idempotency/idempotency.service';
import { FederationConsumerService } from './federation-consumer.service';

type ConsumeCallback = (msg: ConsumeMessage | null) => void;

function envelope(overrides: Partial<MessageEnvelope> = {}): MessageEnvelope {
  return {
    jobId: 'job-1',
    correlationId: 'job-1',
    tenantId: 't-1',
    instanceId: 'inst-1',
    createdAt: new Date().toISOString(),
    attempt: 0,
    payload: {},
    ...overrides,
  };
}

function makeMsg(env: MessageEnvelope, routingKey: string): ConsumeMessage {
  return {
    content: Buffer.from(JSON.stringify(env)),
    fields: { routingKey },
    properties: {},
  } as ConsumeMessage;
}

function flushMicrotasks(): Promise<void> {
  return new Promise((resolve) => setImmediate(resolve));
}

describe('FederationConsumerService', () => {
  let consumeCallback: ConsumeCallback | undefined;
  const channelMock = {
    consume: jest.fn<
      Promise<{ consumerTag: string }>,
      [string, ConsumeCallback, { noAck: boolean }?]
    >((_queue, cb) => {
      consumeCallback = cb;
      return Promise.resolve({ consumerTag: 'tag-1' });
    }),
    ack: jest.fn(),
    nack: jest.fn(),
    publish: jest.fn(),
    once: jest.fn(),
  };
  const connectionMock = {
    isConnected: jest.fn(),
    getChannel: jest.fn(),
  };
  const publisherMock = { publish: jest.fn() };
  const idempotencyMock = { isProcessed: jest.fn(), markProcessed: jest.fn() };
  const instanceSyncHandlerMock = { handle: jest.fn() };
  const serverSyncHandlerMock = { handle: jest.fn() };
  const resourcesCollectHandlerMock = { handle: jest.fn() };

  let service: FederationConsumerService;

  beforeEach(async () => {
    jest.clearAllMocks();
    consumeCallback = undefined;
    connectionMock.isConnected.mockReturnValue(true);
    connectionMock.getChannel.mockReturnValue(channelMock);
    idempotencyMock.isProcessed.mockResolvedValue(false);
    idempotencyMock.markProcessed.mockResolvedValue(undefined);

    service = new FederationConsumerService(
      connectionMock as unknown as RabbitMqConnectionService,
      publisherMock as unknown as RabbitMqPublisherService,
      idempotencyMock as unknown as IdempotencyService,
      instanceSyncHandlerMock as unknown as InstanceSyncHandler,
      serverSyncHandlerMock as unknown as ServerSyncHandler,
      resourcesCollectHandlerMock as unknown as ResourcesCollectHandler,
    );
    service.onModuleInit();
    await flushMicrotasks();
  });

  it('starts consuming from the federation.worker queue with manual ack once connected', () => {
    expect(channelMock.consume.mock.calls[0][0]).toBe(QUEUES.FEDERATION_WORKER);
    expect(channelMock.consume.mock.calls[0][2]).toEqual({ noAck: false });
    expect(consumeCallback).toBeDefined();
  });

  it('acks and dispatches to the right handler on success', async () => {
    instanceSyncHandlerMock.handle.mockResolvedValueOnce(undefined);
    const msg = makeMsg(envelope(), ROUTING_KEYS.INSTANCE_SYNC);

    consumeCallback?.(msg);
    await flushMicrotasks();

    expect(instanceSyncHandlerMock.handle).toHaveBeenCalledWith(
      expect.objectContaining({ jobId: 'job-1' }),
    );
    expect(idempotencyMock.markProcessed).toHaveBeenCalledWith(
      'job-1',
      ROUTING_KEYS.INSTANCE_SYNC,
      't-1',
    );
    expect(channelMock.ack).toHaveBeenCalledWith(msg);
    expect(channelMock.nack).not.toHaveBeenCalled();
  });

  it('skips already-processed jobs (idempotency) and just acks - no handler call', async () => {
    idempotencyMock.isProcessed.mockResolvedValueOnce(true);
    const msg = makeMsg(envelope(), ROUTING_KEYS.SERVER_SYNC);

    consumeCallback?.(msg);
    await flushMicrotasks();

    expect(serverSyncHandlerMock.handle).not.toHaveBeenCalled();
    expect(channelMock.ack).toHaveBeenCalledWith(msg);
  });

  it('publishes unparseable messages straight to the DLX and acks (no retry possible)', async () => {
    const badMsg = {
      content: Buffer.from('not json'),
      fields: { routingKey: ROUTING_KEYS.INSTANCE_SYNC } as ConsumeMessage['fields'],
      properties: {} as ConsumeMessage['properties'],
    } as ConsumeMessage;

    consumeCallback?.(badMsg);
    await flushMicrotasks();

    expect(channelMock.publish).toHaveBeenCalledWith(
      EXCHANGES.DLX,
      ROUTING_KEYS.INSTANCE_SYNC,
      badMsg.content,
      expect.objectContaining({ persistent: true }),
    );
    expect(channelMock.ack).toHaveBeenCalledWith(badMsg);
    expect(instanceSyncHandlerMock.handle).not.toHaveBeenCalled();
  });

  it('sends a permanent-classification failure straight to the DLQ, never retries', async () => {
    instanceSyncHandlerMock.handle.mockRejectedValueOnce(new PterodactylAuthError('bad key'));
    const msg = makeMsg(envelope(), ROUTING_KEYS.INSTANCE_SYNC);

    consumeCallback?.(msg);
    await flushMicrotasks();

    expect(publisherMock.publish).toHaveBeenCalledWith(
      EXCHANGES.DLX,
      ROUTING_KEYS.INSTANCE_SYNC,
      expect.objectContaining({ jobId: 'job-1' }),
      {},
    );
    expect(channelMock.ack).toHaveBeenCalledWith(msg);
    // A permanent failure is a TERMINAL outcome, same as success - marked
    // processed so an accidental redelivery of this exact jobId (e.g. a
    // broker redelivering after an ack that did not land) is recognized
    // as "already handled" instead of landing in the DLQ a second time.
    expect(idempotencyMock.markProcessed).toHaveBeenCalledWith(
      'job-1',
      ROUTING_KEYS.INSTANCE_SYNC,
      't-1',
    );
  });

  it('republishes a transient failure to the retry exchange with an incremented attempt and acks the original', async () => {
    instanceSyncHandlerMock.handle.mockRejectedValueOnce(new Error('ECONNREFUSED'));
    const msg = makeMsg(envelope({ attempt: 0 }), ROUTING_KEYS.INSTANCE_SYNC);

    consumeCallback?.(msg);
    await flushMicrotasks();

    expect(publisherMock.publish).toHaveBeenCalledWith(
      EXCHANGES.RETRY,
      ROUTING_KEYS.INSTANCE_SYNC,
      expect.objectContaining({ jobId: 'job-1', attempt: 1 }),
      { expirationMs: expect.any(Number) as number },
    );
    expect(channelMock.ack).toHaveBeenCalledWith(msg);
    // Not terminal - the retry (same jobId, higher attempt) must still
    // run when it comes back around, so this must NOT be marked processed.
    expect(idempotencyMock.markProcessed).not.toHaveBeenCalled();
  });

  it('sends to the DLQ once retries are exhausted instead of retrying forever', async () => {
    instanceSyncHandlerMock.handle.mockRejectedValueOnce(new Error('still down'));
    const msg = makeMsg(
      envelope({ attempt: MAX_RETRY_ATTEMPTS }),
      ROUTING_KEYS.INSTANCE_SYNC,
    );

    consumeCallback?.(msg);
    await flushMicrotasks();

    expect(publisherMock.publish).toHaveBeenCalledWith(
      EXCHANGES.DLX,
      ROUTING_KEYS.INSTANCE_SYNC,
      expect.objectContaining({ jobId: 'job-1', attempt: MAX_RETRY_ATTEMPTS }),
      {},
    );
    expect(channelMock.ack).toHaveBeenCalledWith(msg);
    expect(idempotencyMock.markProcessed).toHaveBeenCalledWith(
      'job-1',
      ROUTING_KEYS.INSTANCE_SYNC,
      't-1',
    );
  });

  it('skips a redelivery of a job that already reached the DLQ instead of sending it there twice (regression: reproduced live during manual verification)', async () => {
    instanceSyncHandlerMock.handle.mockRejectedValueOnce(new PterodactylAuthError('bad key'));
    const firstDelivery = makeMsg(envelope(), ROUTING_KEYS.INSTANCE_SYNC);
    consumeCallback?.(firstDelivery);
    await flushMicrotasks();
    expect(publisherMock.publish).toHaveBeenCalledTimes(1);

    // isProcessed() is backed by the same idempotencyMock the first
    // delivery just called markProcessed() on - simulate that by making
    // isProcessed() now return true, exactly like a real ProcessedJob
    // lookup would after the row exists.
    idempotencyMock.isProcessed.mockResolvedValueOnce(true);
    const redelivery = makeMsg(envelope(), ROUTING_KEYS.INSTANCE_SYNC);
    consumeCallback?.(redelivery);
    await flushMicrotasks();

    expect(publisherMock.publish).toHaveBeenCalledTimes(1); // still 1, not 2
    expect(channelMock.ack).toHaveBeenCalledWith(redelivery);
    expect(instanceSyncHandlerMock.handle).toHaveBeenCalledTimes(1);
  });

  it('nacks with requeue (never drops the message) when RabbitMQ is down and the retry publish itself fails', async () => {
    instanceSyncHandlerMock.handle.mockRejectedValueOnce(new Error('ECONNREFUSED'));
    publisherMock.publish.mockImplementationOnce(() => {
      throw new Error('RabbitMQ channel is not available (connection down)');
    });
    const msg = makeMsg(envelope(), ROUTING_KEYS.INSTANCE_SYNC);

    consumeCallback?.(msg);
    await flushMicrotasks();

    expect(channelMock.nack).toHaveBeenCalledWith(msg, false, true);
    expect(channelMock.ack).not.toHaveBeenCalled();
  });

  it('dispatches federation.server.sync and federation.resources.collect to their own handlers', async () => {
    serverSyncHandlerMock.handle.mockResolvedValueOnce(undefined);
    resourcesCollectHandlerMock.handle.mockResolvedValueOnce(undefined);

    consumeCallback?.(makeMsg(envelope(), ROUTING_KEYS.SERVER_SYNC));
    await flushMicrotasks();
    consumeCallback?.(makeMsg(envelope({ jobId: 'job-2' }), ROUTING_KEYS.RESOURCES_COLLECT));
    await flushMicrotasks();

    expect(serverSyncHandlerMock.handle).toHaveBeenCalledTimes(1);
    expect(resourcesCollectHandlerMock.handle).toHaveBeenCalledTimes(1);
  });
});
