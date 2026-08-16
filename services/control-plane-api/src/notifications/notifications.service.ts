import { Injectable, Logger, NotFoundException } from '@nestjs/common';
import {
  Notification,
  NotificationChannel,
  NotificationStatus,
} from '@prisma/client';
import { SsrfValidatorService } from '@pterocontrol/pterodactyl-sdk';
import {
  createEnvelope,
  EXCHANGES,
  RabbitMqPublisherService,
  ROUTING_KEYS,
} from '@pterocontrol/rabbitmq';
import { PrismaService } from '../prisma/prisma.service';
import { CreateNotificationChannelDto } from './dto/create-notification-channel.dto';

export interface NotificationFilters {
  channelId?: string;
  alertId?: string;
  status?: NotificationStatus;
}

/**
 * Owns both the NotificationChannel CRUD and the fan-out that turns one
 * newly-triggered Alert into one Notification row (+ one queued job) per
 * enabled channel on that tenant. Sending itself never happens here -
 * that outbound HTTP call is exactly the kind of operation the RabbitMQ
 * mandate says an evaluator/HTTP request must not perform synchronously;
 * NotificationDispatchHandler in federation-worker does the actual POST.
 */
@Injectable()
export class NotificationsService {
  private readonly logger = new Logger(NotificationsService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly ssrfValidator: SsrfValidatorService,
    private readonly publisher: RabbitMqPublisherService,
  ) {}

  async createChannel(
    tenantId: string,
    dto: CreateNotificationChannelDto,
  ): Promise<NotificationChannel> {
    await this.ssrfValidator.assertSafe(dto.url);

    return this.prisma.notificationChannel.create({
      data: {
        tenantId,
        type: dto.type,
        config: { url: dto.url },
      },
    });
  }

  findAllChannelsForTenant(tenantId: string): Promise<NotificationChannel[]> {
    return this.prisma.notificationChannel.findMany({
      where: { tenantId },
      orderBy: { createdAt: 'asc' },
    });
  }

  async removeChannel(tenantId: string, id: string): Promise<void> {
    const channel = await this.prisma.notificationChannel.findFirst({
      where: { id, tenantId },
    });
    if (!channel) {
      throw new NotFoundException('Notification channel not found');
    }
    await this.prisma.notificationChannel.delete({ where: { id: channel.id } });
  }

  findAllNotificationsForTenant(
    tenantId: string,
    filters: NotificationFilters,
  ): Promise<Notification[]> {
    return this.prisma.notification.findMany({
      where: {
        tenantId,
        ...(filters.channelId ? { channelId: filters.channelId } : {}),
        ...(filters.alertId ? { alertId: filters.alertId } : {}),
        ...(filters.status ? { status: filters.status } : {}),
      },
      orderBy: { createdAt: 'desc' },
      take: 200,
    });
  }

  /**
   * Called by AlertsService right after it creates a new (not
   * re-triggered - dedup already happened there) Alert. One enabled
   * channel failing to queue (broker down) is logged and skipped, never
   * allowed to fail the Alert creation itself that already committed -
   * the Alert is real and visible via GET /alerts regardless of whether
   * anyone got notified about it.
   */
  async notifyAlertTriggered(tenantId: string, alertId: string): Promise<void> {
    const channels = await this.prisma.notificationChannel.findMany({
      where: { tenantId, enabled: true },
    });

    for (const channel of channels) {
      const notification = await this.prisma.notification.create({
        data: { tenantId, channelId: channel.id, alertId, status: NotificationStatus.PENDING },
      });

      const envelope = createEnvelope({
        tenantId,
        payload: { notificationId: notification.id },
      });
      try {
        this.publisher.publish(EXCHANGES.EVENTS, ROUTING_KEYS.ALERT_TRIGGERED, envelope);
      } catch (error) {
        this.logger.warn(
          `Could not queue notification ${notification.id} for channel ${channel.id} (tenant ${tenantId}): ${String(error)}`,
        );
      }
    }
  }
}
