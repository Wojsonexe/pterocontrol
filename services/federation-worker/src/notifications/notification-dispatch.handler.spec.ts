import { NotificationChannelType, NotificationStatus } from '@prisma/client';
import { MessageEnvelope } from '@pterocontrol/rabbitmq';
import { PermanentJobError } from '../errors/permanent-job-error';
import { PrismaService } from '../prisma/prisma.service';
import { NotificationDispatchHandler } from './notification-dispatch.handler';
import { WebhookHttpClient, WebhookNetworkError } from './webhook-http.client';

interface NotificationUpdateArgs {
  where: { id: string };
  data: { status: NotificationStatus; lastError?: string; sentAt?: Date; attempt?: number };
}

describe('NotificationDispatchHandler', () => {
  const prismaMock = {
    notification: {
      findFirst: jest.fn(),
      update: jest.fn<Promise<unknown>, [NotificationUpdateArgs]>(),
    },
  };
  const webhookClientMock = { post: jest.fn() };

  let handler: NotificationDispatchHandler;
  const tenantId = 't-1';

  function envelope(payload: Record<string, unknown> = { notificationId: 'notif-1' }): MessageEnvelope {
    return {
      jobId: 'job-1',
      correlationId: 'job-1',
      tenantId,
      createdAt: new Date().toISOString(),
      attempt: 0,
      payload,
    };
  }

  const notification = {
    id: 'notif-1',
    tenantId,
    channelId: 'chan-1',
    alertId: 'alert-1',
    channel: {
      id: 'chan-1',
      type: NotificationChannelType.WEBHOOK,
      config: { url: 'https://ops.example.com/hooks/alerts' },
    },
    alert: {
      id: 'alert-1',
      ruleId: 'rule-1',
      resourceId: 'srv-1',
      triggeredAt: new Date(),
      payload: { observedValue: 95 },
      rule: { id: 'rule-1', name: 'High CPU', metric: 'CPU_PERCENT' },
    },
  };

  beforeEach(() => {
    jest.clearAllMocks();
    handler = new NotificationDispatchHandler(
      prismaMock as unknown as PrismaService,
      webhookClientMock as unknown as WebhookHttpClient,
    );
  });

  it('throws PermanentJobError when the envelope is missing payload.notificationId', async () => {
    await expect(handler.handle(envelope({}))).rejects.toThrow(PermanentJobError);
    expect(prismaMock.notification.findFirst).not.toHaveBeenCalled();
  });

  it('throws PermanentJobError when the notification does not belong to the tenant', async () => {
    prismaMock.notification.findFirst.mockResolvedValueOnce(null);

    await expect(handler.handle(envelope())).rejects.toThrow(PermanentJobError);
  });

  it('throws PermanentJobError when the channel has no url configured', async () => {
    prismaMock.notification.findFirst.mockResolvedValueOnce({
      ...notification,
      channel: { ...notification.channel, config: {} },
    });

    await expect(handler.handle(envelope())).rejects.toThrow(PermanentJobError);
    expect(webhookClientMock.post).not.toHaveBeenCalled();
  });

  it('POSTs the webhook and marks the Notification DELIVERED on success', async () => {
    prismaMock.notification.findFirst.mockResolvedValueOnce(notification);
    webhookClientMock.post.mockResolvedValueOnce(undefined);
    prismaMock.notification.update.mockResolvedValueOnce({});

    await handler.handle(envelope());

    expect(webhookClientMock.post).toHaveBeenCalledWith(
      'https://ops.example.com/hooks/alerts',
      expect.objectContaining({ alertId: 'alert-1', ruleId: 'rule-1' }),
    );
    const updateArgs = prismaMock.notification.update.mock.calls[0][0];
    expect(updateArgs.where).toEqual({ id: 'notif-1' });
    expect(updateArgs.data.status).toBe(NotificationStatus.DELIVERED);
  });

  it('marks the Notification FAILED and rethrows unwrapped when the webhook send fails', async () => {
    prismaMock.notification.findFirst.mockResolvedValueOnce(notification);
    const networkError = new WebhookNetworkError('ECONNREFUSED');
    webhookClientMock.post.mockRejectedValueOnce(networkError);
    prismaMock.notification.update.mockResolvedValueOnce({});

    await expect(handler.handle(envelope())).rejects.toBe(networkError);

    const updateArgs = prismaMock.notification.update.mock.calls[0][0];
    expect(updateArgs.where).toEqual({ id: 'notif-1' });
    expect(updateArgs.data.status).toBe(NotificationStatus.FAILED);
    expect(updateArgs.data.lastError).toBe('ECONNREFUSED');
  });
});
