import { BadGatewayException } from '@nestjs/common';
import { PterodactylAuthError, PterodactylClientApiClient } from '@pterocontrol/pterodactyl-sdk';
import { AuditService } from '../audit/audit.service';
import { ServerCredentialResolverService } from '../servers/server-credential-resolver.service';
import { ServerDatabasesService } from './server-databases.service';

describe('ServerDatabasesService', () => {
  const credentialsMock = { resolveClientApiCredential: jest.fn() };
  const clientApiMock = {
    listServerDatabases: jest.fn(),
    createServerDatabase: jest.fn(),
    rotateServerDatabasePassword: jest.fn(),
    deleteServerDatabase: jest.fn(),
  };
  const auditServiceMock = {
    record: jest.fn<Promise<void>, [{ result: string; metadata: Record<string, unknown> }]>(),
  };

  let service: ServerDatabasesService;
  const tenantId = 't-1';
  const actorId = 'actor-1';
  const resolved = { baseUrl: 'https://panel.example.com', apiKey: 'client-key', identifier: 'd3aac109' };

  beforeEach(() => {
    jest.clearAllMocks();
    service = new ServerDatabasesService(
      credentialsMock as unknown as ServerCredentialResolverService,
      clientApiMock as unknown as PterodactylClientApiClient,
      auditServiceMock as unknown as AuditService,
    );
    credentialsMock.resolveClientApiCredential.mockResolvedValue(resolved);
  });

  it('list maps a Pterodactyl-side failure to BadGatewayException', async () => {
    clientApiMock.listServerDatabases.mockRejectedValueOnce(new PterodactylAuthError('bad key'));

    await expect(service.list(tenantId, 'srv-1')).rejects.toThrow(BadGatewayException);
  });

  it('create passes database name and remote through, never logs the password', async () => {
    clientApiMock.createServerDatabase.mockResolvedValueOnce({
      id: 'db-1',
      name: 's1_survival',
      password: 'super-secret-actual-password',
    });

    await service.create(tenantId, actorId, 'srv-1', { database: 's1_survival', remote: '%' });

    expect(clientApiMock.createServerDatabase).toHaveBeenCalledWith(
      resolved.baseUrl,
      resolved.apiKey,
      resolved.identifier,
      's1_survival',
      '%',
    );
    const auditArgs = auditServiceMock.record.mock.calls[0][0];
    expect(JSON.stringify(auditArgs.metadata)).not.toContain('super-secret-actual-password');
  });

  it('rotatePassword calls the rotate endpoint and records the audit entry without the password', async () => {
    clientApiMock.rotateServerDatabasePassword.mockResolvedValueOnce({
      id: 'db-1',
      password: 'new-secret-password',
    });

    await service.rotatePassword(tenantId, actorId, 'srv-1', 'db-1');

    expect(clientApiMock.rotateServerDatabasePassword).toHaveBeenCalledWith(
      resolved.baseUrl,
      resolved.apiKey,
      resolved.identifier,
      'db-1',
    );
    const auditArgs = auditServiceMock.record.mock.calls[0][0];
    expect(JSON.stringify(auditArgs.metadata)).not.toContain('new-secret-password');
  });

  it('remove records a failure audit entry AND still throws when deletion fails', async () => {
    clientApiMock.deleteServerDatabase.mockRejectedValueOnce(new PterodactylAuthError('bad key'));

    await expect(service.remove(tenantId, actorId, 'srv-1', 'db-1')).rejects.toThrow(
      BadGatewayException,
    );

    const auditArgs = auditServiceMock.record.mock.calls[0][0];
    expect(auditArgs.result).toBe('error');
  });
});
