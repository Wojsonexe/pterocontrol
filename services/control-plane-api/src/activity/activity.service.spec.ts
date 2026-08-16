import { BadGatewayException, NotFoundException } from '@nestjs/common';
import { PterodactylAuthError, PterodactylClientApiClient } from '@pterocontrol/pterodactyl-sdk';
import { ServerCredentialResolverService } from '../servers/server-credential-resolver.service';
import { ActivityService } from './activity.service';

describe('ActivityService', () => {
  const credentialsMock = { resolveClientApiCredential: jest.fn() };
  const clientApiMock = { listActivity: jest.fn() };

  let service: ActivityService;
  const tenantId = 't-1';
  const resolved = { baseUrl: 'https://panel.example.com', apiKey: 'client-key', identifier: 'd3aac109' };

  beforeEach(() => {
    jest.clearAllMocks();
    service = new ActivityService(
      credentialsMock as unknown as ServerCredentialResolverService,
      clientApiMock as unknown as PterodactylClientApiClient,
    );
    credentialsMock.resolveClientApiCredential.mockResolvedValue(resolved);
  });

  it('never calls Pterodactyl for a server in another tenant', async () => {
    credentialsMock.resolveClientApiCredential.mockRejectedValueOnce(
      new NotFoundException('Server not found'),
    );

    await expect(service.list('other-tenant', 'srv-1')).rejects.toThrow(NotFoundException);
    expect(clientApiMock.listActivity).not.toHaveBeenCalled();
  });

  it('fetches activity using the resolved identifier', async () => {
    clientApiMock.listActivity.mockResolvedValueOnce([]);

    await service.list(tenantId, 'srv-1');

    expect(clientApiMock.listActivity).toHaveBeenCalledWith(
      resolved.baseUrl,
      resolved.apiKey,
      resolved.identifier,
    );
  });

  it('maps a Pterodactyl-side failure to BadGatewayException', async () => {
    clientApiMock.listActivity.mockRejectedValueOnce(new PterodactylAuthError('bad key'));

    await expect(service.list(tenantId, 'srv-1')).rejects.toThrow(BadGatewayException);
  });
});
