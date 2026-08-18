import { randomUUID } from 'crypto';

/**
 * Every message on the federation exchanges carries this shape.
 * jobId identifies one logical unit of work and stays the same across
 * every retry of it (attempt increments, jobId does not) - this is
 * what a consumer uses to detect "have I already fully processed
 * this job before" (see ProcessedJob in federation-worker).
 */
export interface MessageEnvelope<TPayload = unknown> {
  jobId: string;
  correlationId: string;
  tenantId: string;
  instanceId?: string;
  serverId?: string;
  createdAt: string;
  attempt: number;
  payload: TPayload;
}

export interface CreateEnvelopeInput<TPayload> {
  tenantId: string;
  instanceId?: string;
  serverId?: string;
  payload: TPayload;
  correlationId?: string;
}

export function createEnvelope<TPayload>(
  input: CreateEnvelopeInput<TPayload>,
): MessageEnvelope<TPayload> {
  const jobId = randomUUID();
  return {
    jobId,
    correlationId: input.correlationId ?? jobId,
    tenantId: input.tenantId,
    instanceId: input.instanceId,
    serverId: input.serverId,
    createdAt: new Date().toISOString(),
    attempt: 0,
    payload: input.payload,
  };
}

/** Used by the worker when republishing a failed job for retry. */
export function withIncrementedAttempt<TPayload>(
  envelope: MessageEnvelope<TPayload>,
): MessageEnvelope<TPayload> {
  return { ...envelope, attempt: envelope.attempt + 1 };
}
