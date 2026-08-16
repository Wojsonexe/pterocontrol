import {
  QUEUES,
  QueueConsumer,
  QueueConsumerHandlers,
  ROUTING_KEYS,
} from '@pterocontrol/rabbitmq';
import { IdempotencyService } from '../idempotency/idempotency.service';
import { NotificationDispatchHandler } from '../notifications/notification-dispatch.handler';
import { NotificationConsumerService } from './notification-consumer.service';

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

describe('NotificationConsumerService', () => {
  const idempotencyMock = { isProcessed: jest.fn(), markProcessed: jest.fn() };
  const notificationDispatchHandlerMock = { handle: jest.fn() };
  const consumerInstanceMock = { start: jest.fn() };

  let service: NotificationConsumerService;

  beforeEach(() => {
    jest.clearAllMocks();
    QueueConsumerMock.mockReturnValue(consumerInstanceMock);
    service = new NotificationConsumerService(
      {} as never,
      {} as never,
      idempotencyMock as unknown as IdempotencyService,
      notificationDispatchHandlerMock as unknown as NotificationDispatchHandler,
    );
  });

  it('constructs a QueueConsumer bound to the notifications.worker queue', () => {
    expect(QueueConsumerMock).toHaveBeenCalledWith(
      {},
      {},
      QUEUES.NOTIFICATIONS_WORKER,
      expect.objectContaining({
        dispatch: expect.any(Function) as unknown,
        classifyError: expect.any(Function) as unknown,
        isProcessed: expect.any(Function) as unknown,
        markProcessed: expect.any(Function) as unknown,
      }),
      NotificationConsumerService.name,
    );
  });

  it('starts the underlying QueueConsumer on module init', () => {
    service.onModuleInit();

    expect(consumerInstanceMock.start).toHaveBeenCalledTimes(1);
  });

  function capturedHandlers(): QueueConsumerHandlers {
    return QueueConsumerMock.mock.calls[0][3];
  }

  it('routes alert.triggered to NotificationDispatchHandler', async () => {
    notificationDispatchHandlerMock.handle.mockResolvedValueOnce(undefined);
    const envelope = {
      jobId: 'job-1',
      correlationId: 'job-1',
      tenantId: 't-1',
      createdAt: new Date().toISOString(),
      attempt: 0,
      payload: { notificationId: 'notif-1' },
    };

    await capturedHandlers().dispatch(ROUTING_KEYS.ALERT_TRIGGERED, envelope);

    expect(notificationDispatchHandlerMock.handle).toHaveBeenCalledWith(envelope);
  });

  it('throws for an unrecognized routing key', async () => {
    const envelope = {
      jobId: 'job-1',
      correlationId: 'job-1',
      tenantId: 't-1',
      createdAt: new Date().toISOString(),
      attempt: 0,
      payload: {},
    };

    await expect(
      capturedHandlers().dispatch('alert.unknown.thing', envelope),
    ).rejects.toThrow('No handler registered');
  });
});
