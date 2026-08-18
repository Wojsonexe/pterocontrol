import { Logger } from '@nestjs/common';
import type { Channel, ConsumeMessage } from 'amqplib';
import { RabbitMqConnectionService } from './connection.service';
import { MessageEnvelope, withIncrementedAttempt } from './envelope';
import { RabbitMqPublisherService } from './publisher.service';
import { computeRetryDelayMs, isRetryExhausted } from './retry';
import { EXCHANGES } from './topology';

const RECONNECT_POLL_MS = 2_000;

export type ErrorClassification = 'permanent' | 'transient';

export interface QueueConsumerHandlers {
  dispatch(routingKey: string, envelope: MessageEnvelope): Promise<void>;
  classifyError(error: unknown): ErrorClassification;
  isProcessed(jobId: string): Promise<boolean>;
  markProcessed(jobId: string, jobType: string, tenantId: string): Promise<void>;
}

/**
 * The whole consume -> dispatch -> ack/retry/DLQ loop, generic over
 * which queue it consumes from and what dispatch/classification/
 * idempotency logic the caller supplies. Factored out of
 * federation-worker's original FederationConsumerService the moment a
 * second queue family (notifications) needed the exact same loop -
 * this logic already had one real, live-reproduced bug (a race between
 * a broker-forced connection closure and channel.consume() on an
 * already-closing channel, crashing the process - see
 * IMPLEMENTATION_STATUS.md FAZA 9b) fixed once here; duplicating it
 * across two consumers would mean fixing every future bug twice and
 * risking the copies drifting, the same reasoning that put
 * SsrfValidatorService/SecretsService in their own shared packages.
 *
 * Manual ack throughout (the channel is created with prefetch(1) by
 * RabbitMqConnectionService) - a message is only ever acked after
 * either full success, a permanent failure explicitly routed to the
 * DLQ, or after its retry has been durably published to cp.retry. It
 * is NEVER acked "because processing finished" without one of those
 * three outcomes, so a worker crash mid-handle() leaves the message
 * unacked and RabbitMQ redelivers it once the connection drops and a
 * fresh one is opened.
 *
 * `queue` determines which queue this instance consumes from; the
 * retry/DLQ exchanges (cp.retry / cp.dlx) are shared constants because
 * routing-key namespace prefixes (`federation.*` vs `alert.*`), not
 * separate exchanges, are what keep the queue families apart - see
 * topology.ts's own doc comment on setupTopology().
 */
export class QueueConsumer {
  private readonly logger: Logger;

  constructor(
    private readonly connection: RabbitMqConnectionService,
    private readonly publisher: RabbitMqPublisherService,
    private readonly queue: string,
    private readonly handlers: QueueConsumerHandlers,
    loggerContext: string,
  ) {
    this.logger = new Logger(loggerContext);
  }

  start(): void {
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
    // a slightly delayed resubscribe.
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
        this.queue,
        (msg) => {
          void this.handleMessage(channel, msg);
        },
        { noAck: false },
      );
      this.logger.log(`Consuming from ${this.queue}`);
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

    if (await this.handlers.isProcessed(envelope.jobId)) {
      this.logger.warn(
        `Job ${envelope.jobId} (${routingKey}) already processed - skipping redelivery`,
      );
      channel.ack(msg);
      return;
    }

    try {
      await this.handlers.dispatch(routingKey, envelope);
      await this.handlers.markProcessed(envelope.jobId, routingKey, envelope.tenantId);
      channel.ack(msg);
    } catch (error) {
      await this.handleFailure(channel, msg, routingKey, envelope, error);
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
    const classification = this.handlers.classifyError(error);

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
      // nack WITH requeue keeps the message on its worker queue rather
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
      await this.handlers.markProcessed(envelope.jobId, routingKey, envelope.tenantId);
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
