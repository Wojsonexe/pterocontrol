import { HttpException } from '@nestjs/common';
import {
  PterodactylAuthError,
  PterodactylNetworkError,
  PterodactylNotFoundError,
  PterodactylUnexpectedResponseError,
  PterodactylUpstreamError,
} from '@pterocontrol/pterodactyl-sdk';
import { PermanentJobError } from '../errors/permanent-job-error';
import { WebhookNetworkError, WebhookResponseError } from '../notifications/webhook-http.client';

export type ErrorClassification = 'permanent' | 'transient';

/**
 * Drives the consumer's retry-vs-DLQ decision (see FederationConsumerService).
 * Mirrors the mandate's own examples exactly:
 *   never retry: 401/403 (bad credential), 404 (nonexistent instance/
 *     endpoint), invalid request (any other non-5xx status), a rejected
 *     SSRF check / malformed URL, or a PermanentJobError raised by a
 *     handler for our own domain reasons (missing instance/credential row).
 *   always retry: network errors (timeout, connection refused - fetch()
 *     itself threw), 502/503/504 and any other 5xx, and an unparseable
 *     response body (could be a flaky proxy/maintenance page - worth
 *     one more try).
 * Anything NOT recognized at all (e.g. a bug in our own Prisma query)
 * defaults to transient - safe, since it is still bounded by
 * MAX_RETRY_ATTEMPTS before landing in the DLQ rather than looping forever.
 */
export function classifyError(error: unknown): ErrorClassification {
  if (error instanceof PermanentJobError) {
    return 'permanent';
  }
  if (error instanceof PterodactylAuthError) {
    return 'permanent';
  }
  if (error instanceof PterodactylNotFoundError) {
    return 'permanent';
  }
  if (error instanceof PterodactylNetworkError) {
    return 'transient';
  }
  if (error instanceof PterodactylUnexpectedResponseError) {
    return 'transient';
  }
  if (error instanceof PterodactylUpstreamError) {
    return error.statusCode !== undefined && error.statusCode >= 500
      ? 'transient'
      : 'permanent';
  }
  if (error instanceof WebhookNetworkError) {
    return 'transient';
  }
  if (error instanceof WebhookResponseError) {
    return error.statusCode !== undefined && error.statusCode >= 500
      ? 'transient'
      : 'permanent';
  }
  if (error instanceof HttpException) {
    return 'permanent';
  }
  return 'transient';
}
