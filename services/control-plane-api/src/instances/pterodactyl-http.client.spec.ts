import {
  PterodactylAuthError,
  PterodactylHttpClient,
  PterodactylNetworkError,
  PterodactylNotFoundError,
  PterodactylUpstreamError,
} from './pterodactyl-http.client';
import { SsrfValidatorService } from './ssrf-validator.service';

describe('PterodactylHttpClient', () => {
  const ssrfMock = { assertSafe: jest.fn() };
  let client: PterodactylHttpClient;
  const originalFetch = global.fetch;

  beforeEach(() => {
    ssrfMock.assertSafe.mockReset();
    ssrfMock.assertSafe.mockResolvedValue(undefined);
    client = new PterodactylHttpClient(
      ssrfMock as unknown as SsrfValidatorService,
    );
  });

  afterEach(() => {
    global.fetch = originalFetch;
  });

  it('validates SSRF for the fully-resolved URL before every request', async () => {
    global.fetch = jest
      .fn()
      .mockResolvedValue(new Response(JSON.stringify({ data: [] }), { status: 200 }));

    await client.get('https://panel.example.com', '/api/application/nodes', 'key');

    expect(ssrfMock.assertSafe).toHaveBeenCalledWith(
      'https://panel.example.com/api/application/nodes',
    );
  });

  it('never calls fetch when SSRF validation rejects the URL', async () => {
    ssrfMock.assertSafe.mockRejectedValueOnce(new Error('blocked'));
    global.fetch = jest.fn();

    await expect(client.get('https://panel.example.com', '/x', 'key')).rejects.toThrow(
      'blocked',
    );
    expect(global.fetch).not.toHaveBeenCalled();
  });

  it('maps 401/403 to PterodactylAuthError', async () => {
    global.fetch = jest.fn().mockResolvedValue(new Response('', { status: 401 }));
    await expect(client.get('https://panel.example.com', '/x', 'key')).rejects.toThrow(
      PterodactylAuthError,
    );
  });

  it('maps 404 to PterodactylNotFoundError', async () => {
    global.fetch = jest.fn().mockResolvedValue(new Response('', { status: 404 }));
    await expect(client.get('https://panel.example.com', '/x', 'key')).rejects.toThrow(
      PterodactylNotFoundError,
    );
  });

  it('maps 5xx to PterodactylUpstreamError', async () => {
    global.fetch = jest.fn().mockResolvedValue(new Response('', { status: 502 }));
    await expect(client.get('https://panel.example.com', '/x', 'key')).rejects.toThrow(
      PterodactylUpstreamError,
    );
  });

  it('maps a thrown network error to PterodactylNetworkError', async () => {
    global.fetch = jest.fn().mockRejectedValue(new TypeError('fetch failed'));
    await expect(client.get('https://panel.example.com', '/x', 'key')).rejects.toThrow(
      PterodactylNetworkError,
    );
  });

  it('rejects a 3xx response instead of following it', async () => {
    global.fetch = jest.fn().mockResolvedValue(new Response('', { status: 302 }));
    await expect(client.get('https://panel.example.com', '/x', 'key')).rejects.toThrow(
      PterodactylUpstreamError,
    );
  });

  it('returns the parsed JSON body on success', async () => {
    global.fetch = jest
      .fn()
      .mockResolvedValue(new Response(JSON.stringify({ hello: 'world' }), { status: 200 }));

    await expect(
      client.get('https://panel.example.com', '/x', 'key'),
    ).resolves.toEqual({ hello: 'world' });
  });
});
