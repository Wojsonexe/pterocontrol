import { BadRequestException, NotFoundException } from '@nestjs/common';
import { SecretsService } from '@pterocontrol/secrets';
import { InstancesService } from '../instances/instances.service';
import { PrismaService } from '../prisma/prisma.service';
import { ServerCredentialResolverService } from './server-credential-resolver.service';
import { ServersService } from './servers.service';

describe('ServerCredentialResolverService', () => {
  const prismaMock = { instanceCredential: { findUnique: jest.fn() } };
  const instancesServiceMock = { findOneForTenant: jest.fn() };
  const serversServiceMock = { findOneForTenant: jest.fn() };
  const secretsMock = { decrypt: jest.fn() };

  let service: ServerCredentialResolverService;
  const tenantId = 't-1';
  const server = { id: 'srv-1', tenantId, instanceId: 'inst-1', identifier: 'd3aac109' };
  const instance = { id: 'inst-1', tenantId, baseUrl: 'https://panel.example.com' };

  beforeEach(() => {
    jest.clearAllMocks();
    service = new ServerCredentialResolverService(
      prismaMock as unknown as PrismaService,
      instancesServiceMock as unknown as InstancesService,
      serversServiceMock as unknown as ServersService,
      secretsMock as unknown as SecretsService,
    );
  });

  it('never decrypts anything for a server in another tenant', async () => {
    serversServiceMock.findOneForTenant.mockRejectedValueOnce(
      new NotFoundException('Server not found'),
    );

    await expect(
      service.resolveClientApiCredential('other-tenant', 'srv-1'),
    ).rejects.toThrow(NotFoundException);
    expect(secretsMock.decrypt).not.toHaveBeenCalled();
  });

  it('resolves baseUrl/apiKey/identifier using the CLIENT_API_KEY credential', async () => {
    serversServiceMock.findOneForTenant.mockResolvedValueOnce(server);
    instancesServiceMock.findOneForTenant.mockResolvedValueOnce(instance);
    prismaMock.instanceCredential.findUnique.mockResolvedValueOnce({
      ciphertext: Buffer.from('enc'),
    });
    secretsMock.decrypt.mockReturnValueOnce('client-key');

    const result = await service.resolveClientApiCredential(tenantId, 'srv-1');

    expect(result).toEqual({
      baseUrl: instance.baseUrl,
      apiKey: 'client-key',
      identifier: 'd3aac109',
    });
  });

  it('rejects with a clear error when no Client API key is configured', async () => {
    serversServiceMock.findOneForTenant.mockResolvedValueOnce(server);
    instancesServiceMock.findOneForTenant.mockResolvedValueOnce(instance);
    prismaMock.instanceCredential.findUnique.mockResolvedValueOnce(null);

    await expect(service.resolveClientApiCredential(tenantId, 'srv-1')).rejects.toThrow(
      BadRequestException,
    );
  });
});
