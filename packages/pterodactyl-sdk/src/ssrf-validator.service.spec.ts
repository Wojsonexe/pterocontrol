import { BadRequestException } from '@nestjs/common';
import { promises as dns } from 'dns';
import { parseTrustedOrigins, SsrfValidatorService } from './ssrf-validator.service';

jest.mock('dns', () => ({
  promises: {
    resolve4: jest.fn(),
    resolve6: jest.fn(),
  },
}));

const resolve4Mock = dns.resolve4 as jest.Mock;
const resolve6Mock = dns.resolve6 as jest.Mock;

describe('SsrfValidatorService', () => {
  let service: SsrfValidatorService;

  beforeEach(() => {
    resolve4Mock.mockReset();
    resolve6Mock.mockReset();
    service = new SsrfValidatorService();
  });

  it('accepts a https URL that resolves to a public IPv4 address', async () => {
    resolve4Mock.mockResolvedValueOnce(['203.0.113.10']);
    resolve6Mock.mockRejectedValueOnce(new Error('no AAAA'));

    await expect(
      service.assertSafe('https://panel.example.com'),
    ).resolves.toBeUndefined();
  });

  it('rejects http:// (non-https scheme)', async () => {
    await expect(service.assertSafe('http://panel.example.com')).rejects.toThrow(
      BadRequestException,
    );
    expect(resolve4Mock).not.toHaveBeenCalled();
  });

  it('rejects a disallowed port', async () => {
    await expect(
      service.assertSafe('https://panel.example.com:22'),
    ).rejects.toThrow(BadRequestException);
  });

  it('rejects a malformed URL', async () => {
    await expect(service.assertSafe('not a url')).rejects.toThrow(
      BadRequestException,
    );
  });

  it('rejects when the host cannot be resolved at all', async () => {
    resolve4Mock.mockRejectedValueOnce(new Error('NXDOMAIN'));
    resolve6Mock.mockRejectedValueOnce(new Error('NXDOMAIN'));

    await expect(
      service.assertSafe('https://does-not-exist.invalid'),
    ).rejects.toThrow(BadRequestException);
  });

  it.each([
    ['loopback', '127.0.0.1'],
    ['private 10/8', '10.1.2.3'],
    ['private 172.16/12', '172.20.1.1'],
    ['private 192.168/16', '192.168.1.1'],
    ['link-local incl. metadata', '169.254.169.254'],
    ['this-network', '0.0.0.0'],
    ['multicast', '224.0.0.1'],
  ])('rejects IPv4 %s (%s)', async (_label, address) => {
    resolve4Mock.mockResolvedValueOnce([address]);
    resolve6Mock.mockRejectedValueOnce(new Error('no AAAA'));

    await expect(
      service.assertSafe('https://panel.example.com'),
    ).rejects.toThrow(BadRequestException);
  });

  it.each([
    ['loopback', '::1'],
    ['link-local', 'fe80::1'],
    ['unique-local fc00::/7 (fc)', 'fc00::1'],
    ['unique-local fc00::/7 (fd)', 'fd12:3456::1'],
    ['IPv4-mapped private address', '::ffff:10.0.0.5'],
  ])('rejects IPv6 %s (%s)', async (_label, address) => {
    resolve4Mock.mockRejectedValueOnce(new Error('no A'));
    resolve6Mock.mockResolvedValueOnce([address]);

    await expect(
      service.assertSafe('https://panel.example.com'),
    ).rejects.toThrow(BadRequestException);
  });

  it('accepts an IP literal directly when it is public', async () => {
    await expect(
      service.assertSafe('https://203.0.113.10'),
    ).resolves.toBeUndefined();
    expect(resolve4Mock).not.toHaveBeenCalled();
  });

  it('rejects an IP literal directly when it is private', async () => {
    await expect(
      service.assertSafe('https://192.168.1.1'),
    ).rejects.toThrow(BadRequestException);
  });

  it('rejects when a public and a private address both resolve (any bad address blocks the whole host)', async () => {
    resolve4Mock.mockResolvedValueOnce(['203.0.113.10', '10.0.0.1']);
    resolve6Mock.mockRejectedValueOnce(new Error('no AAAA'));

    await expect(
      service.assertSafe('https://panel.example.com'),
    ).rejects.toThrow(BadRequestException);
  });

  describe('assertSafeHost with allowPrivate:true (DatabaseGatewayService)', () => {
    it.each([
      ['private 10/8', '10.1.2.3'],
      ['private 172.16/12', '172.20.1.1'],
      ['private 192.168/16', '192.168.1.1'],
      ['IPv6 unique-local', 'fc00::1'],
      ['IPv4-mapped private address', '::ffff:10.0.0.5'],
    ])('allows %s (%s) - a node database host is routinely RFC1918', async (_label, address) => {
      const isV6 = address.includes(':');
      if (isV6) {
        resolve4Mock.mockRejectedValueOnce(new Error('no A'));
        resolve6Mock.mockResolvedValueOnce([address]);
      } else {
        resolve4Mock.mockResolvedValueOnce([address]);
        resolve6Mock.mockRejectedValueOnce(new Error('no AAAA'));
      }

      await expect(
        service.assertSafeHost('db.internal', { allowPrivate: true }),
      ).resolves.toBeUndefined();
    });

    it.each([
      ['loopback', '127.0.0.1'],
      ['link-local incl. metadata', '169.254.169.254'],
      ['this-network', '0.0.0.0'],
      ['multicast', '224.0.0.1'],
    ])('still rejects %s (%s) even with allowPrivate:true - never a legitimate database host', async (_label, address) => {
      resolve4Mock.mockResolvedValueOnce([address]);
      resolve6Mock.mockRejectedValueOnce(new Error('no AAAA'));

      await expect(
        service.assertSafeHost('db.internal', { allowPrivate: true }),
      ).rejects.toThrow(BadRequestException);
    });

    it('still rejects IPv6 loopback/link-local with allowPrivate:true', async () => {
      resolve4Mock.mockRejectedValueOnce(new Error('no A'));
      resolve6Mock.mockResolvedValueOnce(['::1']);

      await expect(
        service.assertSafeHost('db.internal', { allowPrivate: true }),
      ).rejects.toThrow(BadRequestException);
    });

    it('defaults to allowPrivate:false when no options are given (same as assertSafe)', async () => {
      resolve4Mock.mockResolvedValueOnce(['10.0.0.1']);
      resolve6Mock.mockRejectedValueOnce(new Error('no AAAA'));

      await expect(service.assertSafeHost('db.internal')).rejects.toThrow(BadRequestException);
    });
  });

  describe('parseTrustedOrigins', () => {
    it('returns an empty array when unset', () => {
      expect(parseTrustedOrigins(undefined)).toEqual([]);
      expect(parseTrustedOrigins('')).toEqual([]);
    });

    it('parses a comma-separated list into normalized origin strings', () => {
      expect(
        parseTrustedOrigins('http://10.10.10.109, HTTPS://Panel.Example.com:8443'),
      ).toEqual(['http://10.10.10.109', 'https://panel.example.com:8443']);
    });

    it('silently drops malformed entries instead of throwing', () => {
      expect(parseTrustedOrigins('not a url, http://10.10.10.109')).toEqual([
        'http://10.10.10.109',
      ]);
    });
  });

  describe('assertSafeInstanceUrl (operator-trusted private Pterodactyl instance)', () => {
    it('behaves exactly like assertSafe when no trusted origins are configured', async () => {
      // service (outer beforeEach) has zero trusted origins.
      await expect(
        service.assertSafeInstanceUrl('http://10.10.10.109'),
      ).rejects.toThrow(BadRequestException);
    });

    it('allows an exact-match trusted http:// private origin', async () => {
      const trusted = new SsrfValidatorService(['http://10.10.10.109']);

      await expect(
        trusted.assertSafeInstanceUrl('http://10.10.10.109'),
      ).resolves.toBeUndefined();
      // No DNS lookup for an IP literal - matches assertSafe's own
      // "accepts an IP literal directly" behavior above.
      expect(resolve4Mock).not.toHaveBeenCalled();
    });

    it('still enforces the strict path for a DIFFERENT private origin the operator did not allowlist', async () => {
      const trusted = new SsrfValidatorService(['http://10.10.10.109']);

      await expect(
        trusted.assertSafeInstanceUrl('http://10.10.10.200'),
      ).rejects.toThrow(BadRequestException);
    });

    it('does not trust a different scheme on an otherwise-matching host:port', async () => {
      const trusted = new SsrfValidatorService(['http://10.10.10.109']);

      await expect(
        trusted.assertSafeInstanceUrl('https://10.10.10.109'),
      ).rejects.toThrow(BadRequestException);
    });

    it('does not trust a different port on an otherwise-matching host', async () => {
      const trusted = new SsrfValidatorService(['http://10.10.10.109']);

      await expect(
        trusted.assertSafeInstanceUrl('http://10.10.10.109:8080'),
      ).rejects.toThrow(BadRequestException);
    });

    it.each([
      ['loopback', 'http://127.0.0.1'],
      ['link-local metadata', 'http://169.254.169.254'],
      ['this-network', 'http://0.0.0.0'],
    ])(
      'still rejects %s (%s) even when it matches the trusted origin string exactly',
      async (_label, trustedButDangerous) => {
        // The allowlist itself would never legitimately contain one of
        // these, but the check must not trust the operator's config
        // blindly - isBlockedAddress's loopback/link-local/metadata/
        // multicast rules apply unconditionally, same as
        // DatabaseGatewayService's allowPrivate:true call site.
        const trusted = new SsrfValidatorService([trustedButDangerous]);

        await expect(
          trusted.assertSafeInstanceUrl(trustedButDangerous),
        ).rejects.toThrow(BadRequestException);
      },
    );

    it('a trusted origin does not make an UNRELATED public host bypass the private-IP block for arbitrary ones', async () => {
      const trusted = new SsrfValidatorService(['http://10.10.10.109']);
      resolve4Mock.mockResolvedValueOnce(['10.5.5.5']);
      resolve6Mock.mockRejectedValueOnce(new Error('no AAAA'));

      await expect(
        trusted.assertSafeInstanceUrl('https://some-other-host.example.com'),
      ).rejects.toThrow(BadRequestException);
    });

    it('still accepts a normal public https:// instance when trusted origins are configured for something else', async () => {
      const trusted = new SsrfValidatorService(['http://10.10.10.109']);
      resolve4Mock.mockResolvedValueOnce(['203.0.113.10']);
      resolve6Mock.mockRejectedValueOnce(new Error('no AAAA'));

      await expect(
        trusted.assertSafeInstanceUrl('https://panel.example.com'),
      ).resolves.toBeUndefined();
    });
  });
});
