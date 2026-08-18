import type { ConsumeMessage } from 'amqplib';
import { RabbitMqConnectionService } from './connection.service';
import { MessageEnvelope } from './envelope';
import { RabbitMqPublisherService } from './publisher.service';
import { MAX_RETRY_ATTEMPTS } from './retry';
import { EXCHANGES } from './topology';
import { QueueConsumer } from './queue-consumer';

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

describe('QueueConsumer', () => {
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
    once: jest.fn<void, [string, () => void]>(),
  };
  const connectionMock = {
    isConnected: jest.fn(),
    getChannel: jest.fn(),
  };
  const publisherMock = { publish: jest.fn() };
  const handlersMock = {
    dispatch: jest.fn<Promise<void>, [string, MessageEnvelope]>(),
    classifyError: jest.fn<'permanent' | 'transient', [unknown]>(),
    isProcessed: jest.fn<Promise<boolean>, [string]>(),
    markProcessed: jest.fn<Promise<void>, [string, string, string]>(),
  };

  const TEST_QUEUE = 'test.worker';
  const TEST_ROUTING_KEY = 'test.job.run';

  beforeEach(async () => {
    jest.clearAllMocks();
    consumeCallback = undefined;
    connectionMock.isConnected.mockReturnValue(true);
    connectionMock.getChannel.mockReturnValue(channelMock);
    handlersMock.isProcessed.mockResolvedValue(false);
    handlersMock.markProcessed.mockResolvedValue(undefined);

    const consumer = new QueueConsumer(
      connectionMock as unknown as RabbitMqConnectionService,
      publisherMock as unknown as RabbitMqPublisherService,
      TEST_QUEUE,
      handlersMock,
      'TestConsumer',
    );
    consumer.start();
    await flushMicrotasks();
  });

  it('starts consuming from the configured queue with manual ack once connected', () => {
    expect(channelMock.consume.mock.calls[0][0]).toBe(TEST_QUEUE);
    expect(channelMock.consume.mock.calls[0][2]).toEqual({ noAck: false });
    expect(consumeCallback).toBeDefined();
  });

  it('acks and dispatches on success', async () => {
    handlersMock.dispatch.mockResolvedValueOnce(undefined);
    const msg = makeMsg(envelope(), TEST_ROUTING_KEY);

    consumeCallback?.(msg);
    await flushMicrotasks();

    expect(handlersMock.dispatch).toHaveBeenCalledWith(
      TEST_ROUTING_KEY,
      expect.objectContaining({ jobId: 'job-1' }),
    );
    expect(handlersMock.markProcessed).toHaveBeenCalledWith('job-1', TEST_ROUTING_KEY, 't-1');
    expect(channelMock.ack).toHaveBeenCalledWith(msg);
    expect(channelMock.nack).not.toHaveBeenCalled();
  });

  it('skips already-processed jobs (idempotency) and just acks - no dispatch', async () => {
    handlersMock.isProcessed.mockResolvedValueOnce(true);
    const msg = makeMsg(envelope(), TEST_ROUTING_KEY);

    consumeCallback?.(msg);
    await flushMicrotasks();

    expect(handlersMock.dispatch).not.toHaveBeenCalled();
    expect(channelMock.ack).toHaveBeenCalledWith(msg);
  });

  it('publishes unparseable messages straight to the DLX and acks (no retry possible)', async () => {
    const badMsg = {
      content: Buffer.from('not json'),
      fields: { routingKey: TEST_ROUTING_KEY },
      properties: {},
    } as ConsumeMessage;

    consumeCallback?.(badMsg);
    await flushMicrotasks();

    expect(channelMock.publish).toHaveBeenCalledWith(
      EXCHANGES.DLX,
      TEST_ROUTING_KEY,
      badMsg.content,
      expect.objectContaining({ persistent: true }),
    );
    expect(channelMock.ack).toHaveBeenCalledWith(badMsg);
    expect(handlersMock.dispatch).not.toHaveBeenCalled();
  });

  it('sends a permanent-classification failure straight to the DLQ, never retries, and marks it processed (terminal outcome)', async () => {
    handlersMock.dispatch.mockRejectedValueOnce(new Error('bad request'));
    handlersMock.classifyError.mockReturnValueOnce('permanent');
    const msg = makeMsg(envelope(), TEST_ROUTING_KEY);

    consumeCallback?.(msg);
    await flushMicrotasks();

    expect(publisherMock.publish).toHaveBeenCalledWith(
      EXCHANGES.DLX,
      TEST_ROUTING_KEY,
      expect.objectContaining({ jobId: 'job-1' }),
      {},
    );
    expect(channelMock.ack).toHaveBeenCalledWith(msg);
    expect(handlersMock.markProcessed).toHaveBeenCalledWith('job-1', TEST_ROUTING_KEY, 't-1');
  });

  it('republishes a transient failure to the retry exchange with an incremented attempt, acks the original, does not mark processed', async () => {
    handlersMock.dispatch.mockRejectedValueOnce(new Error('ECONNREFUSED'));
    handlersMock.classifyError.mockReturnValueOnce('transient');
    const msg = makeMsg(envelope({ attempt: 0 }), TEST_ROUTING_KEY);

    consumeCallback?.(msg);
    await flushMicrotasks();

    expect(publisherMock.publish).toHaveBeenCalledWith(
      EXCHANGES.RETRY,
      TEST_ROUTING_KEY,
      expect.objectContaining({ jobId: 'job-1', attempt: 1 }),
      { expirationMs: expect.any(Number) as number },
    );
    expect(channelMock.ack).toHaveBeenCalledWith(msg);
    expect(handlersMock.markProcessed).not.toHaveBeenCalled();
  });

  it('sends to the DLQ once retries are exhausted instead of retrying forever', async () => {
    handlersMock.dispatch.mockRejectedValueOnce(new Error('still down'));
    handlersMock.classifyError.mockReturnValueOnce('transient');
    const msg = makeMsg(envelope({ attempt: MAX_RETRY_ATTEMPTS }), TEST_ROUTING_KEY);

    consumeCallback?.(msg);
    await flushMicrotasks();

    expect(publisherMock.publish).toHaveBeenCalledWith(
      EXCHANGES.DLX,
      TEST_ROUTING_KEY,
      expect.objectContaining({ jobId: 'job-1', attempt: MAX_RETRY_ATTEMPTS }),
      {},
    );
    expect(channelMock.ack).toHaveBeenCalledWith(msg);
  });

  it('nacks with requeue (never drops the message) when RabbitMQ is down and the retry publish itself fails', async () => {
    handlersMock.dispatch.mockRejectedValueOnce(new Error('ECONNREFUSED'));
    handlersMock.classifyError.mockReturnValueOnce('transient');
    publisherMock.publish.mockImplementationOnce(() => {
      throw new Error('RabbitMQ channel is not available (connection down)');
    });
    const msg = makeMsg(envelope(), TEST_ROUTING_KEY);

    consumeCallback?.(msg);
    await flushMicrotasks();

    expect(channelMock.nack).toHaveBeenCalledWith(msg, false, true);
    expect(channelMock.ack).not.toHaveBeenCalled();
  });

  it('skips a redelivery of a job that already reached the DLQ instead of sending it there twice', async () => {
    handlersMock.dispatch.mockRejectedValueOnce(new Error('bad request'));
    handlersMock.classifyError.mockReturnValueOnce('permanent');
    const firstDelivery = makeMsg(envelope(), TEST_ROUTING_KEY);
    consumeCallback?.(firstDelivery);
    await flushMicrotasks();
    expect(publisherMock.publish).toHaveBeenCalledTimes(1);

    handlersMock.isProcessed.mockResolvedValueOnce(true);
    const redelivery = makeMsg(envelope(), TEST_ROUTING_KEY);
    consumeCallback?.(redelivery);
    await flushMicrotasks();

    expect(publisherMock.publish).toHaveBeenCalledTimes(1); // still 1, not 2
    expect(channelMock.ack).toHaveBeenCalledWith(redelivery);
    expect(handlersMock.dispatch).toHaveBeenCalledTimes(1);
  });

  it('resumes consuming once reconnected after the channel closes', async () => {
    const closeHandler = channelMock.once.mock.calls.find(
      (call) => call[0] === 'close',
    )?.[1];
    expect(closeHandler).toBeDefined();

    channelMock.consume.mockClear();
    closeHandler?.();
    await flushMicrotasks();

    expect(channelMock.consume).toHaveBeenCalledWith(
      TEST_QUEUE,
      expect.any(Function),
      { noAck: false },
    );
  });
});
