import { PterodactylApplicationApiClient } from './pterodactyl-application-api.client';
import { PterodactylHttpClient } from './pterodactyl-http.client';

describe('PterodactylApplicationApiClient', () => {
  const httpMock = { get: jest.fn() };
  let client: PterodactylApplicationApiClient;

  beforeEach(() => {
    httpMock.get.mockReset();
    client = new PterodactylApplicationApiClient(
      httpMock as unknown as PterodactylHttpClient,
    );
  });

  it('unwraps a Fractal-style envelope into a plain array of attributes', async () => {
    httpMock.get.mockResolvedValueOnce({
      data: [
        { attributes: { id: 1, name: 'node-1', fqdn: 'n1.example.com', memory: 8192, disk: 100000 } },
        { attributes: { id: 2, name: 'node-2', fqdn: 'n2.example.com', memory: 8192, disk: 100000 } },
      ],
    });

    const nodes = await client.listNodes('https://panel.example.com', 'key');

    expect(nodes).toEqual([
      { id: 1, name: 'node-1', fqdn: 'n1.example.com', memory: 8192, disk: 100000 },
      { id: 2, name: 'node-2', fqdn: 'n2.example.com', memory: 8192, disk: 100000 },
    ]);
    expect(httpMock.get).toHaveBeenCalledWith(
      'https://panel.example.com',
      '/api/application/nodes?page=1',
      'key',
    );
  });

  it('testConnection() is exactly listNodes(page=1) - no separate endpoint invented', async () => {
    httpMock.get.mockResolvedValueOnce({ data: [] });

    await client.testConnection('https://panel.example.com', 'key');

    expect(httpMock.get).toHaveBeenCalledWith(
      'https://panel.example.com',
      '/api/application/nodes?page=1',
      'key',
    );
  });

  it('rejects a malformed (non-Fractal) response instead of returning garbage', async () => {
    httpMock.get.mockResolvedValueOnce({ not: 'the expected shape' });

    await expect(
      client.listServers('https://panel.example.com', 'key'),
    ).rejects.toThrow(/Fractal/);
  });

  it('propagates errors from the underlying HTTP client unchanged', async () => {
    httpMock.get.mockRejectedValueOnce(new Error('401'));

    await expect(
      client.listNodes('https://panel.example.com', 'key'),
    ).rejects.toThrow('401');
  });
});
