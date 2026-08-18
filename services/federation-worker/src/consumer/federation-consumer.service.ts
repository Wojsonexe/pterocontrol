import { Injectable, OnModuleInit } from '@nestjs/common';
import {
  MessageEnvelope,
  QUEUES,
  QueueConsumer,
  RabbitMqConnectionService,
  RabbitMqPublisherService,
  ROUTING_KEYS,
} from '@pterocontrol/rabbitmq';
import { InstanceSyncHandler } from '../handlers/instance-sync.handler';
import { ResourcesCollectHandler } from '../handlers/resources-collect.handler';
import { ServerSyncHandler } from '../handlers/server-sync.handler';
import { IdempotencyService } from '../idempotency/idempotency.service';
import { classifyError } from '../jobs/job-classifier';

/**
 * Thin wiring around @pterocontrol/rabbitmq's generic QueueConsumer (the
 * consume -> dispatch -> ack/retry/DLQ loop itself lives there now,
 * shared with NotificationConsumerService - see that class and
 * QueueConsumer's own doc comment for why) - this class only supplies
 * federation.worker-specific routing and the three job handlers.
 */
@Injectable()
export class FederationConsumerService implements OnModuleInit {
  private readonly consumer: QueueConsumer;

  constructor(
    connection: RabbitMqConnectionService,
    publisher: RabbitMqPublisherService,
    private readonly idempotency: IdempotencyService,
    private readonly instanceSyncHandler: InstanceSyncHandler,
    private readonly serverSyncHandler: ServerSyncHandler,
    private readonly resourcesCollectHandler: ResourcesCollectHandler,
  ) {
    this.consumer = new QueueConsumer(
      connection,
      publisher,
      QUEUES.FEDERATION_WORKER,
      {
        dispatch: (routingKey, envelope) => this.dispatch(routingKey, envelope),
        classifyError,
        isProcessed: (jobId) => this.idempotency.isProcessed(jobId),
        markProcessed: (jobId, jobType, tenantId) =>
          this.idempotency.markProcessed(jobId, jobType, tenantId),
      },
      FederationConsumerService.name,
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
      case ROUTING_KEYS.INSTANCE_SYNC:
        return this.instanceSyncHandler.handle(envelope);
      case ROUTING_KEYS.SERVER_SYNC:
        return this.serverSyncHandler.handle(envelope);
      case ROUTING_KEYS.RESOURCES_COLLECT:
        return this.resourcesCollectHandler.handle(envelope);
      default:
        throw new Error(`No handler registered for routing key "${routingKey}"`);
    }
  }
}
