import { Injectable } from '@nestjs/common';
import { SsrfValidatorService } from '@pterocontrol/pterodactyl-sdk';

/**
 * Same error taxonomy shape as @pterocontrol/pterodactyl-sdk's
 * PterodactylError hierarchy, deliberately not shared with it - a
 * webhook POST carries no Bearer auth, expects no JSON response body,
 * and hits an arbitrary user-supplied URL rather than a Pterodactyl
 * endpoint, so the two clients diverge enough that a shared base would
 * mostly be indirection. Only federation-worker ever sends webhooks
 * (control-plane-api doesn't), so there is no duplication-across-two-
 * services risk to justify extracting this into a package either.
 */
export class WebhookError extends Error {}
export class WebhookNetworkError extends WebhookError {}
export class WebhookResponseError extends WebhookError {
  constructor(
    message: string,
    public readonly statusCode?: number,
  ) {
    super(message);
  }
}

const DEFAULT_TIMEOUT_MS = 10_000;

/**
 * SSRF-validated outbound POST to a user-configured webhook URL - same
 * security posture as PterodactylHttpClient (re-validated immediately
 * before the call, redirects never followed, timeout via
 * AbortController) even though this is a much smaller, single-purpose
 * client.
 */
@Injectable()
export class WebhookHttpClient {
  constructor(private readonly ssrfValidator: SsrfValidatorService) {}

  async post(
    url: string,
    body: unknown,
    timeoutMs = DEFAULT_TIMEOUT_MS,
  ): Promise<void> {
    await this.ssrfValidator.assertSafe(url);

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), timeoutMs);

    let response: Response;
    try {
      response = await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
        redirect: 'manual',
        signal: controller.signal,
      });
    } catch (error) {
      throw new WebhookNetworkError(
        `Network error contacting webhook ${url}: ${String(error)}`,
      );
    } finally {
      clearTimeout(timeout);
    }

    if (
      response.type === 'opaqueredirect' ||
      (response.status >= 300 && response.status < 400)
    ) {
      throw new WebhookResponseError(
        'Webhook responded with a redirect - redirects are never followed',
      );
    }
    if (!response.ok) {
      throw new WebhookResponseError(
        `Webhook responded with ${response.status}`,
        response.status,
      );
    }
  }
}
