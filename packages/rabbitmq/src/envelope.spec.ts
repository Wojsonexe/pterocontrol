import { createEnvelope, withIncrementedAttempt } from './envelope';

describe('envelope', () => {
  it('generates a fresh jobId, defaults correlationId to it, and starts at attempt 0', () => {
    const envelope = createEnvelope({ tenantId: 't-1', payload: { foo: 'bar' } });

    expect(envelope.jobId).toMatch(/^[0-9a-f-]{36}$/);
    expect(envelope.correlationId).toBe(envelope.jobId);
    expect(envelope.attempt).toBe(0);
    expect(envelope.tenantId).toBe('t-1');
    expect(envelope.payload).toEqual({ foo: 'bar' });
  });

  it('honors an explicit correlationId instead of defaulting to jobId', () => {
    const envelope = createEnvelope({
      tenantId: 't-1',
      payload: {},
      correlationId: 'http-request-123',
    });

    expect(envelope.correlationId).toBe('http-request-123');
    expect(envelope.correlationId).not.toBe(envelope.jobId);
  });

  it('produces a different jobId on every call (never reused across logical jobs)', () => {
    const a = createEnvelope({ tenantId: 't-1', payload: {} });
    const b = createEnvelope({ tenantId: 't-1', payload: {} });

    expect(a.jobId).not.toBe(b.jobId);
  });

  it('withIncrementedAttempt() keeps jobId and correlationId stable, only bumps attempt', () => {
    const original = createEnvelope({ tenantId: 't-1', payload: { x: 1 } });

    const retried = withIncrementedAttempt(original);

    expect(retried.jobId).toBe(original.jobId);
    expect(retried.correlationId).toBe(original.correlationId);
    expect(retried.attempt).toBe(1);
    expect(retried.payload).toEqual(original.payload);
  });
});
