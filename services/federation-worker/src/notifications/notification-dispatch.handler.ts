import { Injectable } from '@nestjs/common';
import { NotificationChannelType, NotificationStatus } from '@prisma/client';
import { MessageEnvelope } from '@pterocontrol/rabbitmq';
import { PermanentJobError } from '../errors/permanent-job-error';
import { PrismaService } from '../prisma/prisma.service';
import { WebhookHttpClient } from './webhook-http.client';

interface AlertTriggeredPayload {
  notificationId?: string;
}

interface WebhookConfig {
  url?: string;
}

/**
 * Consumes federation.notifications.worker (alert.triggered), sends the
 * actual outbound webhook POST, and writes the delivery outcome back to
 * the Notification row NotificationsService already created PENDING.
 * status is updated to FAILED even on a transient error that will still
 * be retried (not just on the final terminal failure) - it reflects
 * "the last attempt's outcome" for operator visibility via GET
 * /notifications, not "delivery is permanently abandoned"; a later
 * successful retry flips it to DELIVERED same as any first attempt would.
 */
@Injectable()
export class NotificationDispatchHandler {
  constructor(
    private readonly prisma: PrismaService,
    private readonly webhookClient: WebhookHttpClient,
  ) {}

  async handle(envelope: MessageEnvelope): Promise<void> {
    const payload = envelope.payload as AlertTriggeredPayload;
    const notificationId = payload.notificationId;
    if (!notificationId) {
      throw new PermanentJobError(
        'alert.triggered envelope is missing payload.notificationId',
      );
    }

    const notification = await this.prisma.notification.findFirst({
      where: { id: notificationId, tenantId: envelope.tenantId },
      include: { channel: true, alert: { include: { rule: true } } },
    });
    if (!notification) {
      throw new PermanentJobError(
        `Notification ${notificationId} not found for tenant ${envelope.tenantId}`,
      );
    }

    // NotificationChannelType has exactly one member today (WEBHOOK), so
    // TypeScript narrows this branch to `never` - kept anyway as
    // future-proofing for a second channel type and as a defensive check
    // against corrupted data, hence the `as string` cast on the message.
    const channelType: string = notification.channel.type;
    if (channelType !== (NotificationChannelType.WEBHOOK as string)) {
      throw new PermanentJobError(`Unsupported notification channel type ${channelType}`);
    }

    const config = notification.channel.config as WebhookConfig;
    if (!config.url) {
      throw new PermanentJobError(
        `Notification channel ${notification.channelId} has no url configured`,
      );
    }

    const body = {
      alertId: notification.alert.id,
      ruleId: notification.alert.ruleId,
      ruleName: notification.alert.rule.name,
      metric: notification.alert.rule.metric,
      resourceId: notification.alert.resourceId,
      triggeredAt: notification.alert.triggeredAt,
      payload: notification.alert.payload,
    };

    try {
      await this.webhookClient.post(config.url, body);
      await this.prisma.notification.update({
        where: { id: notification.id },
        data: {
          status: NotificationStatus.DELIVERED,
          sentAt: new Date(),
          attempt: envelope.attempt,
        },
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      await this.prisma.notification.update({
        where: { id: notification.id },
        data: { status: NotificationStatus.FAILED, lastError: message, attempt: envelope.attempt },
      });
      throw error; // propagate unwrapped for the consumer's retry/DLQ classification
    }
  }
}
