import { BadRequestException, Injectable } from '@nestjs/common';
import { promises as dns } from 'dns';
import { isIP } from 'net';

const ALLOWED_SCHEMES = new Set(['https:']);
const ALLOWED_PORTS = new Set(['', '443', '8443']);

/**
 * Parses the `TRUSTED_PTERODACTYL_ORIGINS` env var (comma-separated
 * exact origins, e.g. "http://10.10.10.109") into the normalized form
 * SsrfValidatorService compares against. Exported so both apps'
 * PterodactylModule can build the same list from the same raw string
 * without duplicating the parsing/normalization logic.
 *
 * Malformed entries are silently dropped, not thrown on - a typo in an
 * operator's optional allowlist should fall back to "not trusted"
 * (the safe direction), not crash the app at startup the way a missing
 * *required* var does in env.validation.ts.
 */
export function parseTrustedOrigins(raw: string | undefined): string[] {
  if (!raw) return [];
  const origins: string[] = [];
  for (const entry of raw.split(',')) {
    const trimmed = entry.trim();
    if (!trimmed) continue;
    try {
      const url = new URL(trimmed);
      origins.push(`${url.protocol}//${url.host}`.toLowerCase());
    } catch {
      // Not a parseable URL - dropped, see doc comment above.
    }
  }
  return origins;
}

/**
 * Validates that a Pterodactyl instance baseUrl is safe for the backend
 * to make outbound requests to, before it's persisted AND again
 * immediately before every actual connection attempt (the second check
 * is what defends against DNS rebinding - a hostname that resolved to a
 * public IP when the instance was added could resolve to something
 * internal by the time a sync job actually connects).
 */
@Injectable()
export class SsrfValidatorService {
  private readonly trustedOrigins: ReadonlySet<string>;

  constructor(trustedOrigins: readonly string[] = []) {
    this.trustedOrigins = new Set(trustedOrigins.map((o) => o.toLowerCase()));
  }

  async assertSafe(rawUrl: string): Promise<void> {
    const url = this.parseUrl(rawUrl);
    this.assertAllowedScheme(url);
    this.assertAllowedPort(url);
    await this.assertSafeHost(url.hostname);
  }

  /**
   * Same intent as `assertSafe`, for exactly one additional case: a URL
   * whose scheme+host+port exactly matches an operator-configured entry
   * in `TRUSTED_PTERODACTYL_ORIGINS` skips the HTTPS-only/port-allowlist
   * rules and the private-IP block - loopback/link-local/metadata/
   * multicast are STILL always rejected even for a trusted origin (via
   * `assertSafeHost(..., { allowPrivate: true })`, the same mechanism
   * already used below for DatabaseGatewayService).
   *
   * Deliberately a separate method, not a parameter on `assertSafe`:
   * `assertSafe`'s other callers (webhook URLs in
   * federation-worker's WebhookHttpClient, notification-channel URLs in
   * NotificationsService) take arbitrary, tenant-supplied targets and
   * must never be able to opt into this - keeping them on the
   * unmodified `assertSafe` means that stays true by construction, not
   * by convention. Only call sites that exclusively ever see
   * `PterodactylInstance.baseUrl` (InstancesService, InstanceSyncHandler,
   * and PterodactylHttpClient - the shared transport both
   * PterodactylApplicationApiClient and PterodactylClientApiClient route
   * every request through) use this method.
   *
   * The allowlist is an exact origin match, not a CIDR/private-range
   * toggle, on purpose: trusting one fixed, operator-chosen origin lets
   * a tenant reach exactly that one pre-approved address and nothing
   * else - they cannot pivot to a different private host by supplying a
   * different baseUrl, unlike a blanket "allow all 10.0.0.0/8" would.
   * Prefer an IP-literal entry (e.g. "http://10.10.10.109") over a
   * hostname when configuring this: an IP literal never touches DNS
   * (see resolveHost's isIP short-circuit), so it has zero DNS-rebinding
   * surface; a hostname-based trusted origin would still be re-resolved
   * on every call and only get the loopback/link-local/metadata/
   * multicast checks, not the full private-range block.
   */
  async assertSafeInstanceUrl(rawUrl: string): Promise<void> {
    const url = this.parseUrl(rawUrl);
    const origin = `${url.protocol}//${url.host}`.toLowerCase();
    if (this.trustedOrigins.has(origin)) {
      await this.assertSafeHost(url.hostname, { allowPrivate: true });
      return;
    }
    this.assertAllowedScheme(url);
    this.assertAllowedPort(url);
    await this.assertSafeHost(url.hostname);
  }

  /**
   * The same address-resolution/blocklist check as `assertSafe`, without
   * the https-only/port-allowlist rules - for callers that open a
   * non-HTTP connection to a host they don't control the scheme/port of.
   * Added for `DatabaseGatewayService` (control-plane-api): the MySQL
   * host/port it connects to comes from a Pterodactyl instance's own API
   * response (a database-provisioning call), not from this app's own
   * config - a compromised or malicious panel could report an internal
   * address (e.g. a cloud metadata IP) as the "database host" and get
   * this backend to open a raw TCP connection to it, the same class of
   * risk `assertSafe` exists to block for `PterodactylInstance.baseUrl`.
   *
   * `allowPrivate` (default `false`, `assertSafe`'s behaviour) exists for
   * exactly that caller: a Pterodactyl node's own database host is
   * routinely an RFC1918 address by design (the game node and its MySQL
   * host typically share a private network) - blocking all private
   * ranges there would break the common, legitimate deployment instead of
   * a real attack. With `allowPrivate: true`, RFC1918/ULA ranges are
   * permitted but loopback and link-local/metadata addresses (never a
   * legitimate database host) are still rejected.
   */
  async assertSafeHost(hostname: string, options?: { allowPrivate?: boolean }): Promise<void> {
    const allowPrivate = options?.allowPrivate ?? false;
    const addresses = await this.resolveHost(hostname);
    if (addresses.length === 0) {
      throw new BadRequestException(`Could not resolve host: ${hostname}`);
    }

    for (const address of addresses) {
      if (this.isBlockedAddress(address, allowPrivate)) {
        throw new BadRequestException(
          `${hostname} resolves to a loopback, link-local, metadata, or otherwise disallowed address (${address})`,
        );
      }
    }
  }

  private parseUrl(rawUrl: string): URL {
    try {
      return new URL(rawUrl);
    } catch {
      throw new BadRequestException('Invalid URL');
    }
  }

  private assertAllowedScheme(url: URL): void {
    if (!ALLOWED_SCHEMES.has(url.protocol)) {
      throw new BadRequestException(
        `Only https:// URLs are allowed, got ${url.protocol}`,
      );
    }
  }

  private assertAllowedPort(url: URL): void {
    if (!ALLOWED_PORTS.has(url.port)) {
      throw new BadRequestException(`Port ${url.port} is not allowed`);
    }
  }

  private async resolveHost(hostname: string): Promise<string[]> {
    if (isIP(hostname)) {
      return [hostname];
    }

    const [v4, v6] = await Promise.allSettled([
      dns.resolve4(hostname),
      dns.resolve6(hostname),
    ]);

    const addresses: string[] = [];
    if (v4.status === 'fulfilled') addresses.push(...v4.value);
    if (v6.status === 'fulfilled') addresses.push(...v6.value);
    return addresses;
  }

  private isBlockedAddress(address: string, allowPrivate: boolean): boolean {
    const version = isIP(address);
    if (version === 4) return this.isBlockedIPv4(address, allowPrivate);
    if (version === 6) return this.isBlockedIPv6(address, allowPrivate);
    return true; // not a syntactically valid IP - block defensively
  }

  private isBlockedIPv4(address: string, allowPrivate: boolean): boolean {
    const octets = address.split('.').map(Number);
    if (octets.length !== 4 || octets.some((o) => Number.isNaN(o))) {
      return true;
    }
    const [a, b] = octets;

    if (a === 127) return true; // loopback (127.0.0.0/8) - never a legitimate remote host
    if (a === 169 && b === 254) return true; // link-local incl. 169.254.169.254 metadata
    if (a === 0) return true; // "this network" (0.0.0.0/8)
    if (a >= 224) return true; // multicast + reserved (224.0.0.0/4 and above)
    if (allowPrivate) return false;
    if (a === 10) return true; // private (10.0.0.0/8)
    if (a === 172 && b >= 16 && b <= 31) return true; // private (172.16.0.0/12)
    if (a === 192 && b === 168) return true; // private (192.168.0.0/16)
    return false;
  }

  private isBlockedIPv6(address: string, allowPrivate: boolean): boolean {
    const normalized = address.toLowerCase();

    if (normalized === '::1' || normalized === '::') return true; // loopback / unspecified
    if (normalized.startsWith('fe80:')) return true; // link-local (fe80::/10)
    if (!allowPrivate && (normalized.startsWith('fc') || normalized.startsWith('fd'))) {
      return true; // unique local (fc00::/7)
    }

    // IPv4-mapped IPv6 (::ffff:a.b.c.d) - re-check the embedded IPv4
    // address rather than letting it slip past the checks above.
    const mappedMatch = /^::ffff:(\d+\.\d+\.\d+\.\d+)$/.exec(normalized);
    if (mappedMatch) {
      return this.isBlockedIPv4(mappedMatch[1], allowPrivate);
    }

    return false;
  }
}
