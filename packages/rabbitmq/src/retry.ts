/**
 * attempt 0 (first failure) -> 5s, attempt 1 -> 15s, attempt 2 -> 30s,
 * attempt 3+ -> exhausted, caller sends to DLQ instead of retrying.
 * MAX_RETRY_ATTEMPTS=3 means 4 total tries (1 initial + 3 retries),
 * matching the brief's own example exactly.
 */
export const MAX_RETRY_ATTEMPTS = 3;

const BASE_DELAYS_MS = [5_000, 15_000, 30_000];

/** +/- 20% jitter so many jobs that failed at the same instant (e.g. a
 * Pterodactyl instance going down) don't all retry in lockstep. */
const JITTER_RATIO = 0.2;

export function isRetryExhausted(attempt: number): boolean {
  return attempt >= MAX_RETRY_ATTEMPTS;
}

export function computeRetryDelayMs(
  attempt: number,
  random: () => number = Math.random,
): number {
  const base = BASE_DELAYS_MS[Math.min(attempt, BASE_DELAYS_MS.length - 1)];
  const jitterSpan = base * JITTER_RATIO;
  const jitter = (random() * 2 - 1) * jitterSpan; // uniform in [-jitterSpan, +jitterSpan]
  return Math.max(0, Math.round(base + jitter));
}
