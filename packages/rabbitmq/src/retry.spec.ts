import { computeRetryDelayMs, isRetryExhausted, MAX_RETRY_ATTEMPTS } from './retry';

describe('retry backoff', () => {
  it('exposes exactly 3 retry attempts (4 total tries) matching the spec example', () => {
    expect(MAX_RETRY_ATTEMPTS).toBe(3);
    expect(isRetryExhausted(0)).toBe(false);
    expect(isRetryExhausted(1)).toBe(false);
    expect(isRetryExhausted(2)).toBe(false);
    expect(isRetryExhausted(3)).toBe(true);
    expect(isRetryExhausted(4)).toBe(true);
  });

  it('uses base delays of 5s / 15s / 30s for attempts 0/1/2, no jitter (random=0.5 = midpoint)', () => {
    const noJitter = () => 0.5; // (0.5*2-1)=0 -> jitter term is exactly 0
    expect(computeRetryDelayMs(0, noJitter)).toBe(5_000);
    expect(computeRetryDelayMs(1, noJitter)).toBe(15_000);
    expect(computeRetryDelayMs(2, noJitter)).toBe(30_000);
  });

  it('caps at the 30s base for any attempt beyond the table', () => {
    const noJitter = () => 0.5;
    expect(computeRetryDelayMs(10, noJitter)).toBe(30_000);
  });

  it('applies up to +/-20% jitter, never negative', () => {
    const maxJitter = () => 1; // (1*2-1)=1 -> +20%
    const minJitter = () => 0; // (0*2-1)=-1 -> -20%

    expect(computeRetryDelayMs(0, maxJitter)).toBe(6_000); // 5000 * 1.2
    expect(computeRetryDelayMs(0, minJitter)).toBe(4_000); // 5000 * 0.8
  });

  it('with real Math.random, stays within the expected jitter band across many samples', () => {
    for (let i = 0; i < 200; i++) {
      const delay = computeRetryDelayMs(0);
      expect(delay).toBeGreaterThanOrEqual(4_000);
      expect(delay).toBeLessThanOrEqual(6_000);
    }
  });
});
