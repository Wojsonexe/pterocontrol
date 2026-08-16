import { BadRequestException } from '@nestjs/common';
import { promises as dns } from 'dns';
import { SsrfValidatorService } from './ssrf-validator.service';

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
});
