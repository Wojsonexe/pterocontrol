import { Injectable } from '@nestjs/common';
import { SsrfValidatorService } from './ssrf-validator.service';

/**
 * Error taxonomy mirrors the one already proven in the Flutter mobile
 * app's AppException hierarchy (NetworkException/UnauthorizedException/
 * NotFoundException/ServerException/InvalidResponseException) - same
 * shape, same reasoning, just the TypeScript side of the same problem.
 */
export class PterodactylError extends Error {}
export class PterodactylAuthError extends PterodactylError {}
export class PterodactylNotFoundError extends PterodactylError {}
export class PterodactylNetworkError extends PterodactylError {}
// statusCode is what lets a caller (e.g. federation-worker's retry
// classifier) tell a transient 5xx from a permanent 4xx without parsing
// the message string - undefined for the redirect case, which has no
// single status (see assertNotRedirect: opaqueredirect has status 0).
export class PterodactylUpstreamError extends PterodactylError {
  constructor(
    message: string,
    public readonly statusCode?: number,
  ) {
    super(message);
  }
}
export class PterodactylUnexpectedResponseError extends PterodactylError {}

const DEFAULT_TIMEOUT_MS = 10_000;

/**
 * Generic HTTP transport for talking to a Pterodactyl instance - knows
 * nothing about specific endpoints (that's PterodactylApplicationApiClient/
 * PterodactylClientApiClient), only how to make a safe, typed request:
 * SSRF-validated (re-checked on every single call, not just at
 * instance-creation time - see SsrfValidatorService's own doc comment
 * on why that matters for DNS rebinding), timed out, redirects never
 * followed, every failure mode mapped to a typed error.
 */
@Injectable()
export class PterodactylHttpClient {
  constructor(private readonly ssrfValidator: SsrfValidatorService) {}

  get(baseUrl: string, path: string, apiKey: string, timeoutMs = DEFAULT_TIMEOUT_MS): Promise<unknown> {
    return this.request(baseUrl, path, apiKey, 'GET', undefined, timeoutMs);
  }

  post(
    baseUrl: string,
    path: string,
    apiKey: string,
    body: unknown,
    timeoutMs = DEFAULT_TIMEOUT_MS,
  ): Promise<unknown> {
    return this.request(baseUrl, path, apiKey, 'POST', body, timeoutMs);
  }

  delete(baseUrl: string, path: string, apiKey: string, timeoutMs = DEFAULT_TIMEOUT_MS): Promise<unknown> {
    return this.request(baseUrl, path, apiKey, 'DELETE', undefined, timeoutMs);
  }

  put(
    baseUrl: string,
    path: string,
    apiKey: string,
    body: unknown,
    timeoutMs = DEFAULT_TIMEOUT_MS,
  ): Promise<unknown> {
    return this.request(baseUrl, path, apiKey, 'PUT', body, timeoutMs);
  }

  private async request(
    baseUrl: string,
    path: string,
    apiKey: string,
    method: 'GET' | 'POST' | 'DELETE' | 'PUT',
    body: unknown,
    timeoutMs: number,
  ): Promise<unknown> {
    const url = new URL(path, baseUrl).toString();
    await this.ssrfValidator.assertSafe(url);

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), timeoutMs);

    let response: Response;
    try {
      response = await fetch(url, {
        method,
        headers: {
          Authorization: `Bearer ${apiKey}`,
          Accept: 'application/json',
          ...(body !== undefined ? { 'Content-Type': 'application/json' } : {}),
        },
        body: body !== undefined ? JSON.stringify(body) : undefined,
        redirect: 'manual',
        signal: controller.signal,
      });
    } catch (error) {
      throw new PterodactylNetworkError(
        `Network error contacting ${baseUrl}: ${String(error)}`,
      );
    } finally {
      clearTimeout(timeout);
    }

    this.assertNotRedirect(response);
    this.assertOk(response);

    // Some endpoints (e.g. the power-action endpoint) legitimately
    // return 204 No Content - only attempt to parse a body if there is one.
    const text = await response.text();
    if (text.length === 0) {
      return undefined;
    }
    try {
      return JSON.parse(text) as unknown;
    } catch (error) {
      throw new PterodactylUnexpectedResponseError(
        `Could not parse response from ${baseUrl} as JSON: ${String(error)}`,
      );
    }
  }

  private assertNotRedirect(response: Response): void {
    // redirect: 'manual' means a real cross-host redirect surfaces as an
    // opaque response (status 0, type 'opaqueredirect') rather than the
    // literal 3xx - checked defensively either way.
    if (
      response.type === 'opaqueredirect' ||
      (response.status >= 300 && response.status < 400)
    ) {
      throw new PterodactylUpstreamError(
        'Instance responded with a redirect - redirects are never followed',
      );
    }
  }

  private assertOk(response: Response): void {
    if (response.status === 401 || response.status === 403) {
      throw new PterodactylAuthError(
        'Pterodactyl instance rejected the API key',
      );
    }
    if (response.status === 404) {
      throw new PterodactylNotFoundError(
        'Endpoint not found on Pterodactyl instance',
      );
    }
    if (response.status >= 500) {
      throw new PterodactylUpstreamError(
        `Pterodactyl instance returned ${response.status}`,
        response.status,
      );
    }
    if (!response.ok) {
      throw new PterodactylUpstreamError(
        `Unexpected status ${response.status}`,
        response.status,
      );
    }
  }
}
