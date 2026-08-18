import { Injectable, OnModuleInit } from '@nestjs/common';
import {
  MessageEnvelope,
  QUEUES,
  QueueConsumer,
  RabbitMqConnectionService,
  RabbitMqPublisherService,
  ROUTING_KEYS,
} from '@pterocontrol/rabbitmq';
import { IdempotencyService } from '../idempotency/idempotency.service';
import { NotificationDispatchHandler } from '../notifications/notification-dispatch.handler';
import { classifyError } from '../jobs/job-classifier';

/**
 * Second QueueConsumer instance in this same process, consuming
 * notifications.worker (alert.triggered) instead of federation.worker -
 * a separate consumer, not a second worker process, since RabbitMQ is
 * what gives real value here (see IMPLEMENTATION_STATUS.md), not a
 * process boundary. Shares the exact same generic loop as
 * FederationConsumerService via @pterocontrol/rabbitmq's QueueConsumer.
 */
@Injectable()
export class NotificationConsumerService implements OnModuleInit {
  private readonly consumer: QueueConsumer;

  constructor(
    connection: RabbitMqConnectionService,
    publisher: RabbitMqPublisherService,
    private readonly idempotency: IdempotencyService,
    private readonly notificationDispatchHandler: NotificationDispatchHandler,
  ) {
    this.consumer = new QueueConsumer(
      connection,
      publisher,
      QUEUES.NOTIFICATIONS_WORKER,
      {
        dispatch: (routingKey, envelope) => this.dispatch(routingKey, envelope),
        classifyError,
        isProcessed: (jobId) => this.idempotency.isProcessed(jobId),
        markProcessed: (jobId, jobType, tenantId) =>
          this.idempotency.markProcessed(jobId, jobType, tenantId),
      },
      NotificationConsumerService.name,
    );
  }

  onModuleInit(): void {
    this.consumer.start();
  }

  private async dispatch(
    routingKey: string,
    envelope: MessageEnvelope,
  ): Promise<void> {
    switch (routingKey) {
      case ROUTING_KEYS.ALERT_TRIGGERED:
        return this.notificationDispatchHandler.handle(envelope);
      default:
        throw new Error(`No handler registered for routing key "${routingKey}"`);
    }
  }
}
