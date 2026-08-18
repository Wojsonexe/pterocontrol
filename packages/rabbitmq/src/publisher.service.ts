import { Injectable, Logger } from '@nestjs/common';
import { RabbitMqConnectionService } from './connection.service';
import { MessageEnvelope } from './envelope';

export interface PublishOptions {
  /** Sets the AMQP `expiration` property (ms, as a string) - used
   *  exclusively for the retry-delay mechanism (see topology.ts). */
  expirationMs?: number;
}

@Injectable()
export class RabbitMqPublisherService {
  private readonly logger = new Logger(RabbitMqPublisherService.name);

  constructor(private readonly connection: RabbitMqConnectionService) {}

  /**
   * Throws if the broker connection is down (RabbitMqConnectionService.
   * getChannel() throws synchronously) - callers must catch this and
   * return a controlled error to their own caller, not let it bubble
   * into a generic 500.
   */
  publish(
    exchange: string,
    routingKey: string,
    envelope: MessageEnvelope,
    options?: PublishOptions,
  ): void {
    const channel = this.connection.getChannel();
    const content = Buffer.from(JSON.stringify(envelope));

    const published = channel.publish(exchange, routingKey, content, {
      persistent: true,
      contentType: 'application/json',
      messageId: envelope.jobId,
      correlationId: envelope.correlationId,
      timestamp: Date.now(),
      headers: { attempt: envelope.attempt },
      ...(options?.expirationMs !== undefined
        ? { expiration: String(options.expirationMs) }
        : {}),
    });

    if (!published) {
      this.logger.warn(
        `Publish buffer full for ${exchange}/${routingKey} (jobId=${envelope.jobId}) - amqplib still queued it, broker is applying backpressure`,
      );
    }
  }
}
