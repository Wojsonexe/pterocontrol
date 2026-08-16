import type { Channel } from 'amqplib';

/**
 * The whole RabbitMQ topology in one place, so control-plane-api
 * (publisher) and federation-worker (consumer) can never define it
 * differently - both call setupTopology() with the same channel type
 * at startup, and RabbitMQ treats re-asserting identical
 * exchanges/queues as a no-op (asserting with *different* properties
 * on an existing entity is what throws, not re-asserting the same ones).
 */
export const EXCHANGES = {
  /** Control Plane API -> federation-worker: "please do this". */
  FEDERATION_COMMANDS: 'cp.federation',
  /** Workers -> anything that cares: "this happened" (Postgres Event
   *  table is still the source of truth - this is transport only). */
  EVENTS: 'cp.events',
  /** Internal holding pen for delayed retries - see setupTopology(). */
  RETRY: 'cp.retry',
  /** Final resting place for messages that exhausted all retries. */
  DLX: 'cp.dlx',
} as const;

export const QUEUES = {
  FEDERATION_WORKER: 'federation.worker',
  FEDERATION_RETRY: 'federation.retry',
  FEDERATION_DLQ: 'federation.dlq',
} as const;

export const ROUTING_KEYS = {
  INSTANCE_SYNC: 'federation.instance.sync',
  SERVER_SYNC: 'federation.server.sync',
  RESOURCES_COLLECT: 'federation.resources.collect',
} as const;

export type FederationRoutingKey =
  (typeof ROUTING_KEYS)[keyof typeof ROUTING_KEYS];

/**
 * Idempotent topology setup. Retry mechanism: a message that needs to
 * be retried is re-published (by the worker, not RabbitMQ) to the
 * RETRY exchange with a per-message `expiration` (its computed backoff
 * delay) and the SAME routing key as the original. federation.retry
 * has no consumer - it exists purely to hold messages until their TTL
 * expires, at which point RabbitMQ dead-letters them back to
 * cp.federation, and (because x-dead-letter-routing-key is left
 * unset) they keep their original routing key, landing back on
 * federation.worker exactly like a fresh message. This gives
 * per-message variable delay (5s/15s/30s) without needing three
 * separate queues or the delayed-message plugin.
 */
export async function setupTopology(channel: Channel): Promise<void> {
  await channel.assertExchange(EXCHANGES.FEDERATION_COMMANDS, 'topic', {
    durable: true,
  });
  await channel.assertExchange(EXCHANGES.EVENTS, 'topic', { durable: true });
  await channel.assertExchange(EXCHANGES.RETRY, 'topic', { durable: true });
  await channel.assertExchange(EXCHANGES.DLX, 'topic', { durable: true });

  await channel.assertQueue(QUEUES.FEDERATION_WORKER, { durable: true });
  await channel.bindQueue(
    QUEUES.FEDERATION_WORKER,
    EXCHANGES.FEDERATION_COMMANDS,
    'federation.#',
  );

  await channel.assertQueue(QUEUES.FEDERATION_RETRY, {
    durable: true,
    deadLetterExchange: EXCHANGES.FEDERATION_COMMANDS,
    // No deadLetterRoutingKey override: each message dead-letters back
    // under its own original routing key once its `expiration` elapses.
  });
  await channel.bindQueue(QUEUES.FEDERATION_RETRY, EXCHANGES.RETRY, '#');

  await channel.assertQueue(QUEUES.FEDERATION_DLQ, { durable: true });
  await channel.bindQueue(QUEUES.FEDERATION_DLQ, EXCHANGES.DLX, '#');
}
