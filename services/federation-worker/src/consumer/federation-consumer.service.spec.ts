import {
  MessageEnvelope,
  QUEUES,
  QueueConsumer,
  QueueConsumerHandlers,
  ROUTING_KEYS,
} from '@pterocontrol/rabbitmq';
import { InstanceSyncHandler } from '../handlers/instance-sync.handler';
import { ResourcesCollectHandler } from '../handlers/resources-collect.handler';
import { ServerSyncHandler } from '../handlers/server-sync.handler';
import { IdempotencyService } from '../idempotency/idempotency.service';
import { FederationConsumerService } from './federation-consumer.service';

jest.mock('@pterocontrol/rabbitmq', () => {
  const actual = jest.requireActual<Record<string, unknown>>('@pterocontrol/rabbitmq');
  return {
    ...actual,
    QueueConsumer: jest.fn(),
  };
});

const QueueConsumerMock = QueueConsumer as unknown as jest.Mock<
  Pick<QueueConsumer, 'start'>,
  [unknown, unknown, string, QueueConsumerHandlers, string]
>;

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

describe('FederationConsumerService', () => {
  const idempotencyMock = { isProcessed: jest.fn(), markProcessed: jest.fn() };
  const instanceSyncHandlerMock = { handle: jest.fn() };
  const serverSyncHandlerMock = { handle: jest.fn() };
  const resourcesCollectHandlerMock = { handle: jest.fn() };
  const consumerInstanceMock = { start: jest.fn() };

  let service: FederationConsumerService;

  beforeEach(() => {
    jest.clearAllMocks();
    QueueConsumerMock.mockReturnValue(consumerInstanceMock);
    service = new FederationConsumerService(
      {} as never, // RabbitMqConnectionService - just passed through to QueueConsumer, never touched directly
      {} as never, // RabbitMqPublisherService - same
      idempotencyMock as unknown as IdempotencyService,
      instanceSyncHandlerMock as unknown as InstanceSyncHandler,
      serverSyncHandlerMock as unknown as ServerSyncHandler,
      resourcesCollectHandlerMock as unknown as ResourcesCollectHandler,
    );
  });

  it('constructs a QueueConsumer bound to the federation.worker queue', () => {
    expect(QueueConsumerMock).toHaveBeenCalledWith(
      {},
      {},
      QUEUES.FEDERATION_WORKER,
      expect.objectContaining({
        dispatch: expect.any(Function) as unknown,
        classifyError: expect.any(Function) as unknown,
        isProcessed: expect.any(Function) as unknown,
        markProcessed: expect.any(Function) as unknown,
      }),
      FederationConsumerService.name,
    );
  });

  it('starts the underlying QueueConsumer on module init', () => {
    service.onModuleInit();

    expect(consumerInstanceMock.start).toHaveBeenCalledTimes(1);
  });

  function capturedHandlers(): QueueConsumerHandlers {
    return QueueConsumerMock.mock.calls[0][3];
  }

  describe('dispatch routing (via the handlers passed to QueueConsumer)', () => {
    it('routes federation.instance.sync to InstanceSyncHandler', async () => {
      instanceSyncHandlerMock.handle.mockResolvedValueOnce(undefined);

      await capturedHandlers().dispatch(ROUTING_KEYS.INSTANCE_SYNC, envelope());

      expect(instanceSyncHandlerMock.handle).toHaveBeenCalledWith(
        expect.objectContaining({ jobId: 'job-1' }),
      );
    });

    it('routes federation.server.sync to ServerSyncHandler', async () => {
      serverSyncHandlerMock.handle.mockResolvedValueOnce(undefined);

      await capturedHandlers().dispatch(ROUTING_KEYS.SERVER_SYNC, envelope());

      expect(serverSyncHandlerMock.handle).toHaveBeenCalled();
    });

    it('routes federation.resources.collect to ResourcesCollectHandler', async () => {
      resourcesCollectHandlerMock.handle.mockResolvedValueOnce(undefined);

      await capturedHandlers().dispatch(ROUTING_KEYS.RESOURCES_COLLECT, envelope());

      expect(resourcesCollectHandlerMock.handle).toHaveBeenCalled();
    });

    it('throws for an unrecognized routing key', async () => {
      await expect(
        capturedHandlers().dispatch('federation.unknown.thing', envelope()),
      ).rejects.toThrow('No handler registered');
    });

    it('delegates isProcessed/markProcessed to IdempotencyService', async () => {
      idempotencyMock.isProcessed.mockResolvedValueOnce(true);

      await expect(capturedHandlers().isProcessed('job-1')).resolves.toBe(true);
      expect(idempotencyMock.isProcessed).toHaveBeenCalledWith('job-1');

      await capturedHandlers().markProcessed('job-1', ROUTING_KEYS.INSTANCE_SYNC, 't-1');
      expect(idempotencyMock.markProcessed).toHaveBeenCalledWith(
        'job-1',
        ROUTING_KEYS.INSTANCE_SYNC,
        't-1',
      );
    });
  });
});
