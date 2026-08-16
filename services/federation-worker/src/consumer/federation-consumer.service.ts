import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import type { Channel, ConsumeMessage } from 'amqplib';
import {
  computeRetryDelayMs,
  EXCHANGES,
  isRetryExhausted,
  MessageEnvelope,
  QUEUES,
  RabbitMqConnectionService,
  RabbitMqPublisherService,
  ROUTING_KEYS,
  withIncrementedAttempt,
} from '@pterocontrol/rabbitmq';
import { IdempotencyService } from '../idempotency/idempotency.service';
import { InstanceSyncHandler } from '../handlers/instance-sync.handler';
import { ResourcesCollectHandler } from '../handlers/resources-collect.handler';
import { ServerSyncHandler } from '../handlers/server-sync.handler';
import { classifyError } from '../jobs/job-classifier';

const RECONNECT_POLL_MS = 2_000;

/**
 * The whole consume -> dispatch -> ack/retry/DLQ loop for
 * federation.worker. Manual ack throughout (channel created with
 * prefetch(1) by RabbitMqConnectionService) - a message is only ever
 * acked after either full success, a permanent failure explicitly routed
 * to the DLQ, or after its retry has been durably published to cp.retry.
 * It is NEVER acked "because processing finished" without one of those
 * three outcomes, so a worker crash mid-handle() leaves the message
 * unacked and RabbitMQ redelivers it once the connection drops and (for
 * this consumer) a fresh one is opened - exactly the "worker crash
 * mid-processing must not lose the message" requirement.
 */
@Injectable()
export class FederationConsumerService implements OnModuleInit {
  private readonly logger = new Logger(FederationConsumerService.name);

  constructor(
    private readonly connection: RabbitMqConnectionService,
    private readonly publisher: RabbitMqPublisherService,
    private readonly idempotency: IdempotencyService,
    private readonly instanceSyncHandler: InstanceSyncHandler,
    private readonly serverSyncHandler: ServerSyncHandler,
    private readonly resourcesCollectHandler: ResourcesCollectHandler,
  ) {}

  onModuleInit(): void {
    void this.startConsuming();
  }

  private async startConsuming(): Promise<void> {
    while (!this.connection.isConnected()) {
      await this.sleep(RECONNECT_POLL_MS);
    }

    // isConnected() can go stale between this check and the calls below -
    // a broker-forced connection closure (e.g. broker restart) fires
    // RabbitMqConnectionService's own 'close' handler AND this channel's
    // 'close' handler in the same tick, and the two can race: this
    // function can start running again with a channel that is already on
    // its way out. getChannel() throwing, or consume() throwing
    // IllegalOperationError on an already-closing channel, must never be
    // an uncaught rejection here - a crashed worker process is worse than
    // a slightly delayed resubscribe. Real failure mode, not
    // hypothetical: reproduced live by docker stop/start on the broker
    // during manual verification (see IMPLEMENTATION_STATUS.md FAZA 9b).
    let channel: Channel;
    try {
      channel = this.connection.getChannel();
    } catch (error) {
      this.logger.warn(
        `Could not get a channel to start consuming, retrying: ${String(error)}`,
      );
      await this.sleep(RECONNECT_POLL_MS);
      return this.startConsuming();
    }

    // The channel this consumer is attached to closes whenever the
    // underlying connection drops (RabbitMqConnectionService nulls it out
    // and starts its own reconnect timer) - this listener is what makes
    // the worker resume consuming once a new channel comes up, rather
    // than silently going idle forever after one network blip.
    channel.once('close', () => {
      this.logger.warn('Consumer channel closed - will resume once reconnected');
      void this.startConsuming();
    });

    try {
      await channel.consume(
        QUEUES.FEDERATION_WORKER,
        (msg) => {
          void this.handleMessage(channel, msg);
        },
        { noAck: false },
      );
      this.logger.log(`Consuming from ${QUEUES.FEDERATION_WORKER}`);
    } catch (error) {
      this.logger.warn(
        `Could not start consuming (channel closed mid-setup), retrying: ${String(error)}`,
      );
      await this.sleep(RECONNECT_POLL_MS);
      return this.startConsuming();
    }
  }

  private async handleMessage(
    channel: Channel,
    msg: ConsumeMessage | null,
  ): Promise<void> {
    if (!msg) {
      // Broker cancelled the consumer (e.g. queue deleted) - nothing to ack.
      return;
    }

    const routingKey = msg.fields.routingKey;
    let envelope: MessageEnvelope;
    try {
      envelope = JSON.parse(msg.content.toString('utf8')) as MessageEnvelope;
    } catch (error) {
      this.logger.error(
        `Unparseable message on ${routingKey} - publishing raw to DLQ, no retry possible: ${String(error)}`,
      );
      channel.publish(EXCHANGES.DLX, routingKey, msg.content, {
        persistent: true,
        headers: { reason: 'unparseable-json' },
      });
      channel.ack(msg);
      return;
    }

    if (await this.idempotency.isProcessed(envelope.jobId)) {
      this.logger.warn(
        `Job ${envelope.jobId} (${routingKey}) already processed - skipping redelivery`,
      );
      channel.ack(msg);
      return;
    }

    try {
      await this.dispatch(routingKey, envelope);
      await this.idempotency.markProcessed(envelope.jobId, routingKey, envelope.tenantId);
      channel.ack(msg);
    } catch (error) {
      await this.handleFailure(channel, msg, routingKey, envelope, error);
    }
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

  private async handleFailure(
    channel: Channel,
    msg: ConsumeMessage,
    routingKey: string,
    envelope: MessageEnvelope,
    error: unknown,
  ): Promise<void> {
    const message = error instanceof Error ? error.message : String(error);
    const classification = classifyError(error);

    if (classification === 'permanent') {
      this.logger.warn(
        `Permanent failure for job ${envelope.jobId} (${routingKey}): ${message} - sending to DLQ, no retry`,
      );
      await this.sendToDlq(channel, msg, routingKey, envelope, message);
      return;
    }

    if (isRetryExhausted(envelope.attempt)) {
      this.logger.warn(
        `Retries exhausted for job ${envelope.jobId} (${routingKey}) after ${envelope.attempt} attempt(s): ${message} - sending to DLQ`,
      );
      await this.sendToDlq(channel, msg, routingKey, envelope, message);
      return;
    }

    const nextEnvelope = withIncrementedAttempt(envelope);
    const delayMs = computeRetryDelayMs(envelope.attempt);
    this.logger.warn(
      `Transient failure for job ${envelope.jobId} (${routingKey}), retry ${nextEnvelope.attempt} in ~${delayMs}ms: ${message}`,
    );
    try {
      this.publisher.publish(EXCHANGES.RETRY, routingKey, nextEnvelope, {
        expirationMs: delayMs,
      });
      // The retry now durably lives in cp.retry; only now is it safe to
      // ack the original delivery.
      channel.ack(msg);
    } catch (publishError) {
      // Could not even publish the retry (RabbitMQ down mid-handling) -
      // nack WITH requeue keeps the message on federation.worker rather
      // than dropping it; at-least-once still holds even though it will
      // likely fail again immediately until the broker recovers.
      this.logger.error(
        `Could not publish retry for job ${envelope.jobId}: ${String(publishError)} - requeueing original message`,
      );
      channel.nack(msg, false, true);
    }
  }

  private async sendToDlq(
    channel: Channel,
    msg: ConsumeMessage,
    routingKey: string,
    envelope: MessageEnvelope,
    reason: string,
  ): Promise<void> {
    try {
      this.publisher.publish(EXCHANGES.DLX, routingKey, envelope, {});
      // Terminal outcome, same as a success - this jobId will never be
      // retried again by design. Marking it processed here (not just on
      // the success path) is what makes an accidental redelivery of a
      // message that already reached the DLQ get recognized and skipped
      // instead of landing in the DLQ a second time.
      await this.idempotency.markProcessed(envelope.jobId, routingKey, envelope.tenantId);
      channel.ack(msg);
    } catch (publishError) {
      this.logger.error(
        `Could not publish job ${envelope.jobId} to DLQ (original reason: ${reason}): ${String(publishError)} - requeueing original message`,
      );
      channel.nack(msg, false, true);
    }
  }

  private sleep(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }
}
