import { BadGatewayException } from '@nestjs/common';
import {
  PterodactylAuthError,
  PterodactylClientApiClient,
  PterodactylServerDatabaseDto,
} from '@pterocontrol/pterodactyl-sdk';
import { AuditService } from '../audit/audit.service';
import { ServerCredentialResolverService } from '../servers/server-credential-resolver.service';
import { ServerDatabaseCredentialService } from './server-database-credential.service';
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
  const credentialStoreMock = {
    upsert: jest.fn<Promise<void>, [string, string, PterodactylServerDatabaseDto]>(),
    remove: jest.fn<Promise<void>, [string, string]>(),
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
      credentialStoreMock as unknown as ServerDatabaseCredentialService,
    );
    credentialsMock.resolveClientApiCredential.mockResolvedValue(resolved);
  });

  it('list maps a Pterodactyl-side failure to BadGatewayException', async () => {
    clientApiMock.listServerDatabases.mockRejectedValueOnce(new PterodactylAuthError('bad key'));

    await expect(service.list(tenantId, 'srv-1')).rejects.toThrow(BadGatewayException);
  });

  it('create passes database name and remote through, never logs the password', async () => {
    const database: PterodactylServerDatabaseDto = {
      id: 'db-1',
      host: '10.0.0.5',
      port: 3306,
      name: 's1_survival',
      username: 'u1_survival',
      connectionsFrom: '%',
      maxConnections: 0,
      password: 'super-secret-actual-password',
    };
    clientApiMock.createServerDatabase.mockResolvedValueOnce(database);

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
    expect(credentialStoreMock.upsert).toHaveBeenCalledWith(tenantId, 'srv-1', database);
  });

  it('rotatePassword calls the rotate endpoint, records the audit entry without the password, and persists the new credential', async () => {
    const database: PterodactylServerDatabaseDto = {
      id: 'db-1',
      host: '10.0.0.5',
      port: 3306,
      name: 's1_survival',
      username: 'u1_survival',
      connectionsFrom: '%',
      maxConnections: 0,
      password: 'new-secret-password',
    };
    clientApiMock.rotateServerDatabasePassword.mockResolvedValueOnce(database);

    await service.rotatePassword(tenantId, actorId, 'srv-1', 'db-1');

    expect(clientApiMock.rotateServerDatabasePassword).toHaveBeenCalledWith(
      resolved.baseUrl,
      resolved.apiKey,
      resolved.identifier,
      'db-1',
    );
    const auditArgs = auditServiceMock.record.mock.calls[0][0];
    expect(JSON.stringify(auditArgs.metadata)).not.toContain('new-secret-password');
    expect(credentialStoreMock.upsert).toHaveBeenCalledWith(tenantId, 'srv-1', database);
  });

  it('remove records a failure audit entry, still throws when deletion fails, and never removes the stored credential', async () => {
    clientApiMock.deleteServerDatabase.mockRejectedValueOnce(new PterodactylAuthError('bad key'));

    await expect(service.remove(tenantId, actorId, 'srv-1', 'db-1')).rejects.toThrow(
      BadGatewayException,
    );

    const auditArgs = auditServiceMock.record.mock.calls[0][0];
    expect(auditArgs.result).toBe('error');
    expect(credentialStoreMock.remove).not.toHaveBeenCalled();
  });

  it('remove deletes the stored credential once the Pterodactyl-side database is actually gone', async () => {
    clientApiMock.deleteServerDatabase.mockResolvedValueOnce(undefined);

    await service.remove(tenantId, actorId, 'srv-1', 'db-1');

    expect(credentialStoreMock.remove).toHaveBeenCalledWith('srv-1', 'db-1');
  });
});
