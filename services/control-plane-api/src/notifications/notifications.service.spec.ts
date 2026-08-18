import { NotFoundException } from '@nestjs/common';
import { NotificationChannelType, NotificationStatus } from '@prisma/client';
import { SsrfValidatorService } from '@pterocontrol/pterodactyl-sdk';
import { EXCHANGES, RabbitMqPublisherService, ROUTING_KEYS } from '@pterocontrol/rabbitmq';
import { PrismaService } from '../prisma/prisma.service';
import { NotificationsService } from './notifications.service';

describe('NotificationsService', () => {
  const prismaMock = {
    notificationChannel: {
      create: jest.fn(),
      findMany: jest.fn(),
      findFirst: jest.fn(),
      delete: jest.fn(),
    },
    notification: {
      create: jest.fn(),
      findMany: jest.fn(),
    },
  };
  const ssrfMock = { assertSafe: jest.fn() };
  const publisherMock = { publish: jest.fn() };

  let service: NotificationsService;
  const tenantId = 't-1';

  beforeEach(() => {
    jest.clearAllMocks();
    service = new NotificationsService(
      prismaMock as unknown as PrismaService,
      ssrfMock as unknown as SsrfValidatorService,
      publisherMock as unknown as RabbitMqPublisherService,
    );
  });

  describe('createChannel', () => {
    it('runs SSRF validation before touching the database', async () => {
      ssrfMock.assertSafe.mockRejectedValueOnce(new Error('blocked: private IP'));

      await expect(
        service.createChannel(tenantId, {
          type: NotificationChannelType.WEBHOOK,
          url: 'https://169.254.169.254/',
        }),
      ).rejects.toThrow('blocked');
      expect(prismaMock.notificationChannel.create).not.toHaveBeenCalled();
    });

    it('creates a channel with the url wrapped in config', async () => {
      ssrfMock.assertSafe.mockResolvedValueOnce(undefined);
      prismaMock.notificationChannel.create.mockResolvedValueOnce({ id: 'chan-1' });

      await service.createChannel(tenantId, {
        type: NotificationChannelType.WEBHOOK,
        url: 'https://example.com/webhook',
      });

      expect(prismaMock.notificationChannel.create).toHaveBeenCalledWith({
        data: {
          tenantId,
          type: NotificationChannelType.WEBHOOK,
          config: { url: 'https://example.com/webhook' },
        },
      });
    });
  });

  describe('removeChannel', () => {
    it('404s when the channel belongs to another tenant', async () => {
      prismaMock.notificationChannel.findFirst.mockResolvedValueOnce(null);

      await expect(service.removeChannel('other-tenant', 'chan-1')).rejects.toThrow(
        NotFoundException,
      );
      expect(prismaMock.notificationChannel.delete).not.toHaveBeenCalled();
    });
  });

  describe('notifyAlertTriggered', () => {
    it('creates one PENDING Notification and publishes one job per enabled channel', async () => {
      prismaMock.notificationChannel.findMany.mockResolvedValueOnce([
        { id: 'chan-1', tenantId, enabled: true },
        { id: 'chan-2', tenantId, enabled: true },
      ]);
      prismaMock.notification.create
        .mockResolvedValueOnce({ id: 'notif-1' })
        .mockResolvedValueOnce({ id: 'notif-2' });

      await service.notifyAlertTriggered(tenantId, 'alert-1');

      expect(prismaMock.notificationChannel.findMany).toHaveBeenCalledWith({
        where: { tenantId, enabled: true },
      });
      expect(prismaMock.notification.create).toHaveBeenCalledWith({
        data: { tenantId, channelId: 'chan-1', alertId: 'alert-1', status: NotificationStatus.PENDING },
      });
      expect(prismaMock.notification.create).toHaveBeenCalledWith({
        data: { tenantId, channelId: 'chan-2', alertId: 'alert-1', status: NotificationStatus.PENDING },
      });
      expect(publisherMock.publish).toHaveBeenCalledTimes(2);
      expect(publisherMock.publish).toHaveBeenCalledWith(
        EXCHANGES.EVENTS,
        ROUTING_KEYS.ALERT_TRIGGERED,
        expect.objectContaining({ tenantId, payload: { notificationId: 'notif-1' } }),
      );
    });

    it('does nothing when the tenant has no enabled channels', async () => {
      prismaMock.notificationChannel.findMany.mockResolvedValueOnce([]);

      await service.notifyAlertTriggered(tenantId, 'alert-1');

      expect(prismaMock.notification.create).not.toHaveBeenCalled();
      expect(publisherMock.publish).not.toHaveBeenCalled();
    });

    it('does not throw when RabbitMQ is down - logs and continues with the next channel', async () => {
      prismaMock.notificationChannel.findMany.mockResolvedValueOnce([
        { id: 'chan-1', tenantId, enabled: true },
        { id: 'chan-2', tenantId, enabled: true },
      ]);
      prismaMock.notification.create
        .mockResolvedValueOnce({ id: 'notif-1' })
        .mockResolvedValueOnce({ id: 'notif-2' });
      publisherMock.publish.mockImplementationOnce(() => {
        throw new Error('RabbitMQ channel is not available (connection down)');
      });

      await expect(service.notifyAlertTriggered(tenantId, 'alert-1')).resolves.toBeUndefined();

      expect(publisherMock.publish).toHaveBeenCalledTimes(2); // both attempted despite the first failing
    });
  });

  describe('findAllNotificationsForTenant', () => {
    it('always scopes by tenantId and applies optional filters', async () => {
      prismaMock.notification.findMany.mockResolvedValueOnce([]);

      await service.findAllNotificationsForTenant(tenantId, {
        channelId: 'chan-1',
        status: NotificationStatus.FAILED,
      });

      expect(prismaMock.notification.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { tenantId, channelId: 'chan-1', status: NotificationStatus.FAILED },
        }),
      );
    });
  });
});
