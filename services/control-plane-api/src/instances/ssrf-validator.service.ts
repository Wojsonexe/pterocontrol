import { BadRequestException, Injectable } from '@nestjs/common';
import { promises as dns } from 'dns';
import { isIP } from 'net';

const ALLOWED_SCHEMES = new Set(['https:']);
const ALLOWED_PORTS = new Set(['', '443', '8443']);

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
  async assertSafe(rawUrl: string): Promise<void> {
    const url = this.parseUrl(rawUrl);
    this.assertAllowedScheme(url);
    this.assertAllowedPort(url);

    const addresses = await this.resolveHost(url.hostname);
    if (addresses.length === 0) {
      throw new BadRequestException(
        `Could not resolve host: ${url.hostname}`,
      );
    }

    for (const address of addresses) {
      if (this.isBlockedAddress(address)) {
        throw new BadRequestException(
          `${url.hostname} resolves to a private, loopback, link-local, or otherwise disallowed address (${address})`,
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

  private isBlockedAddress(address: string): boolean {
    const version = isIP(address);
    if (version === 4) return this.isBlockedIPv4(address);
    if (version === 6) return this.isBlockedIPv6(address);
    return true; // not a syntactically valid IP - block defensively
  }

  private isBlockedIPv4(address: string): boolean {
    const octets = address.split('.').map(Number);
    if (octets.length !== 4 || octets.some((o) => Number.isNaN(o))) {
      return true;
    }
    const [a, b] = octets;

    if (a === 127) return true; // loopback (127.0.0.0/8)
    if (a === 10) return true; // private (10.0.0.0/8)
    if (a === 172 && b >= 16 && b <= 31) return true; // private (172.16.0.0/12)
    if (a === 192 && b === 168) return true; // private (192.168.0.0/16)
    if (a === 169 && b === 254) return true; // link-local incl. 169.254.169.254 metadata
    if (a === 0) return true; // "this network" (0.0.0.0/8)
    if (a >= 224) return true; // multicast + reserved (224.0.0.0/4 and above)
    return false;
  }

  private isBlockedIPv6(address: string): boolean {
    const normalized = address.toLowerCase();

    if (normalized === '::1' || normalized === '::') return true; // loopback / unspecified
    if (normalized.startsWith('fe80:')) return true; // link-local (fe80::/10)
    if (normalized.startsWith('fc') || normalized.startsWith('fd')) {
      return true; // unique local (fc00::/7)
    }

    // IPv4-mapped IPv6 (::ffff:a.b.c.d) - re-check the embedded IPv4
    // address rather than letting it slip past the checks above.
    const mappedMatch = /^::ffff:(\d+\.\d+\.\d+\.\d+)$/.exec(normalized);
    if (mappedMatch) {
      return this.isBlockedIPv4(mappedMatch[1]);
    }

    return false;
  }
}
