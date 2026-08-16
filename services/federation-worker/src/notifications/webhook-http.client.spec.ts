import { SsrfValidatorService } from '@pterocontrol/pterodactyl-sdk';
import {
  WebhookHttpClient,
  WebhookNetworkError,
  WebhookResponseError,
} from './webhook-http.client';

describe('WebhookHttpClient', () => {
  const ssrfMock = { assertSafe: jest.fn() };
  let client: WebhookHttpClient;
  const originalFetch = global.fetch;

  beforeEach(() => {
    ssrfMock.assertSafe.mockReset();
    ssrfMock.assertSafe.mockResolvedValue(undefined);
    client = new WebhookHttpClient(ssrfMock as unknown as SsrfValidatorService);
  });

  afterEach(() => {
    global.fetch = originalFetch;
  });

  it('validates SSRF for the exact webhook URL before every send', async () => {
    global.fetch = jest.fn().mockResolvedValue(new Response(null, { status: 200 }));

    await client.post('https://ops.example.com/hooks/alerts', { hello: 'world' });

    expect(ssrfMock.assertSafe).toHaveBeenCalledWith('https://ops.example.com/hooks/alerts');
  });

  it('never calls fetch when SSRF validation rejects the URL', async () => {
    ssrfMock.assertSafe.mockRejectedValueOnce(new Error('blocked: private IP'));
    global.fetch = jest.fn();

    await expect(client.post('https://169.254.169.254/', {})).rejects.toThrow('blocked');
    expect(global.fetch).not.toHaveBeenCalled();
  });

  it('sends a JSON body with the correct Content-Type', async () => {
    const fetchMock = jest.fn().mockResolvedValue(new Response(null, { status: 200 }));
    global.fetch = fetchMock;

    await client.post('https://ops.example.com/hooks', { alertId: 'a-1' });

    const [, options] = fetchMock.mock.calls[0] as [string, RequestInit];
    expect(options.method).toBe('POST');
    expect(options.body).toBe(JSON.stringify({ alertId: 'a-1' }));
    expect((options.headers as Record<string, string>)['Content-Type']).toBe(
      'application/json',
    );
  });

  it('succeeds silently on any 2xx response', async () => {
    global.fetch = jest.fn().mockResolvedValue(new Response(null, { status: 204 }));

    await expect(client.post('https://ops.example.com/hooks', {})).resolves.toBeUndefined();
  });

  it('maps a non-2xx response to WebhookResponseError carrying the status code', async () => {
    global.fetch = jest.fn().mockResolvedValue(new Response(null, { status: 404 }));

    await expect(client.post('https://ops.example.com/hooks', {})).rejects.toMatchObject({
      constructor: WebhookResponseError,
      statusCode: 404,
    });
  });

  it('maps a 5xx response to WebhookResponseError with that status code', async () => {
    global.fetch = jest.fn().mockResolvedValue(new Response(null, { status: 503 }));

    await expect(client.post('https://ops.example.com/hooks', {})).rejects.toMatchObject({
      constructor: WebhookResponseError,
      statusCode: 503,
    });
  });

  it('maps a thrown network error to WebhookNetworkError', async () => {
    global.fetch = jest.fn().mockRejectedValue(new TypeError('fetch failed'));

    await expect(client.post('https://ops.example.com/hooks', {})).rejects.toThrow(
      WebhookNetworkError,
    );
  });

  it('rejects a redirect response instead of following it', async () => {
    global.fetch = jest.fn().mockResolvedValue(new Response(null, { status: 302 }));

    await expect(client.post('https://ops.example.com/hooks', {})).rejects.toThrow(
      WebhookResponseError,
    );
  });
});
