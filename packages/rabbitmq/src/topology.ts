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
  /** Workers -> anything that cares: "this happened" (Postgres Event/
   *  Alert tables are still the source of truth - this is transport
   *  only). Two queue families both consume from here now (see QUEUES) -
   *  AlertsService publishes alert.triggered, federation-worker's
   *  instance/server sync handlers could add more event types later. */
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
  NOTIFICATIONS_WORKER: 'notifications.worker',
  NOTIFICATIONS_RETRY: 'notifications.retry',
  NOTIFICATIONS_DLQ: 'notifications.dlq',
} as const;

export const ROUTING_KEYS = {
  INSTANCE_SYNC: 'federation.instance.sync',
  SERVER_SYNC: 'federation.server.sync',
  RESOURCES_COLLECT: 'federation.resources.collect',
  ALERT_TRIGGERED: 'alert.triggered',
} as const;

export type FederationRoutingKey =
  (typeof ROUTING_KEYS)[keyof typeof ROUTING_KEYS];

/**
 * Idempotent topology setup. Retry mechanism: a message that needs to
 * be retried is re-published (by the worker, not RabbitMQ) to the
 * RETRY exchange with a per-message `expiration` (its computed backoff
 * delay) and the SAME routing key as the original. The *.retry queues
 * have no consumer - they exist purely to hold messages until their TTL
 * expires, at which point RabbitMQ dead-letters them back to the
 * originating commands exchange, and (because x-dead-letter-routing-key
 * is left unset) they keep their original routing key, landing back on
 * the right worker queue exactly like a fresh message. This gives
 * per-message variable delay (5s/15s/30s) without needing three
 * separate queues or the delayed-message plugin.
 *
 * Two independent queue families share the same RETRY/DLX exchanges,
 * distinguished by routing-key namespace prefix (`federation.*` vs
 * `alert.*`) - each family's retry-hold queue only binds its own
 * prefix and dead-letters back to its own commands exchange
 * (FEDERATION_COMMANDS vs EVENTS), so a federation retry can never end
 * up on the notifications worker queue or vice versa, even though both
 * retries transit the same cp.retry exchange.
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
  await channel.bindQueue(QUEUES.FEDERATION_RETRY, EXCHANGES.RETRY, 'federation.#');

  await channel.assertQueue(QUEUES.FEDERATION_DLQ, { durable: true });
  await channel.bindQueue(QUEUES.FEDERATION_DLQ, EXCHANGES.DLX, 'federation.#');

  await channel.assertQueue(QUEUES.NOTIFICATIONS_WORKER, { durable: true });
  await channel.bindQueue(
    QUEUES.NOTIFICATIONS_WORKER,
    EXCHANGES.EVENTS,
    'alert.#',
  );

  await channel.assertQueue(QUEUES.NOTIFICATIONS_RETRY, {
    durable: true,
    deadLetterExchange: EXCHANGES.EVENTS,
  });
  await channel.bindQueue(QUEUES.NOTIFICATIONS_RETRY, EXCHANGES.RETRY, 'alert.#');

  await channel.assertQueue(QUEUES.NOTIFICATIONS_DLQ, { durable: true });
  await channel.bindQueue(QUEUES.NOTIFICATIONS_DLQ, EXCHANGES.DLX, 'alert.#');
}
