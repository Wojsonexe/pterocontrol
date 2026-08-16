import { BadGatewayException, BadRequestException } from '@nestjs/common';
import { AuditService } from '../audit/audit.service';
import { ServerDatabaseCredentialService } from '../server-databases/server-database-credential.service';
import { DatabaseGatewayService } from './database-gateway.service';

describe('DatabaseGatewayService', () => {
  const credentialStoreMock = { resolve: jest.fn() };
  const connectionMock = { query: jest.fn(), end: jest.fn() };
  const connectionFactoryMock = { connect: jest.fn() };
  const auditServiceMock = {
    record: jest.fn<Promise<void>, [{ result: string; metadata: Record<string, unknown> }]>(),
  };

  let service: DatabaseGatewayService;
  const tenantId = 't-1';
  const actorId = 'actor-1';
  const credential = {
    host: '10.0.0.5',
    port: 3306,
    databaseName: 's1_survival',
    username: 'u1_survival',
    password: 'super-secret-password',
  };

  beforeEach(() => {
    jest.clearAllMocks();
    service = new DatabaseGatewayService(
      credentialStoreMock as unknown as ServerDatabaseCredentialService,
      connectionFactoryMock,
      auditServiceMock as unknown as AuditService,
    );
    credentialStoreMock.resolve.mockResolvedValue(credential);
    connectionFactoryMock.connect.mockResolvedValue(connectionMock);
    connectionMock.end.mockResolvedValue(undefined);
  });

  it('rejects invalid SQL before ever resolving a credential or opening a connection', async () => {
    await expect(
      service.execute(tenantId, actorId, 'srv-1', 'db-1', 'DROP TABLE players'),
    ).rejects.toThrow(BadRequestException);

    expect(credentialStoreMock.resolve).not.toHaveBeenCalled();
    expect(connectionFactoryMock.connect).not.toHaveBeenCalled();
  });

  it('connects using the resolved credential and closes the connection afterwards', async () => {
    connectionMock.query.mockResolvedValueOnce([[{ id: 1, name: 'alice' }]]);

    await service.execute(tenantId, actorId, 'srv-1', 'db-1', 'SELECT * FROM players');

    expect(connectionFactoryMock.connect).toHaveBeenCalledWith({
      host: credential.host,
      port: credential.port,
      user: credential.username,
      password: credential.password,
      database: credential.databaseName,
    });
    expect(connectionMock.end).toHaveBeenCalled();
  });

  it('returns rows for a SELECT and records success in AuditLog without the SQL result or password', async () => {
    connectionMock.query.mockResolvedValueOnce([[{ id: 1, name: 'alice' }]]);

    const result = await service.execute(tenantId, actorId, 'srv-1', 'db-1', 'SELECT * FROM players');

    expect(result).toEqual({
      kind: 'rows',
      columns: ['id', 'name'],
      rows: [{ id: 1, name: 'alice' }],
      rowCount: 1,
      truncated: false,
    });
    const auditArgs = auditServiceMock.record.mock.calls[0][0];
    expect(auditArgs.result).toBe('success');
    expect(JSON.stringify(auditArgs.metadata)).not.toContain('super-secret-password');
  });

  it('truncates a result set larger than the row cap and reports truncated:true', async () => {
    const bigResult = Array.from({ length: 600 }, (_, i) => ({ id: i }));
    connectionMock.query.mockResolvedValueOnce([bigResult]);

    const result = await service.execute(tenantId, actorId, 'srv-1', 'db-1', 'SELECT * FROM players');

    expect(result.rowCount).toBe(500);
    expect(result.truncated).toBe(true);
  });

  it('returns affectedRows for a write statement', async () => {
    connectionMock.query.mockResolvedValueOnce([{ affectedRows: 3 }]);

    const result = await service.execute(
      tenantId,
      actorId,
      'srv-1',
      'db-1',
      "UPDATE players SET banned = 1 WHERE clan = 'x'",
    );

    expect(result).toEqual({ kind: 'write', affectedRows: 3 });
  });

  it('maps a query failure to BadGatewayException, records failure audit, and still closes the connection', async () => {
    connectionMock.query.mockRejectedValueOnce(new Error('Table players does not exist'));

    await expect(
      service.execute(tenantId, actorId, 'srv-1', 'db-1', 'SELECT * FROM players'),
    ).rejects.toThrow(BadGatewayException);

    const auditArgs = auditServiceMock.record.mock.calls[0][0];
    expect(auditArgs.result).toBe('error');
    expect(connectionMock.end).toHaveBeenCalled();
  });

  it('propagates NotFoundException from the credential store (unknown/foreign database id) without connecting', async () => {
    credentialStoreMock.resolve.mockRejectedValueOnce(new Error('not found'));

    await expect(
      service.execute(tenantId, actorId, 'srv-1', 'unknown-db', 'SELECT 1'),
    ).rejects.toThrow('not found');
    expect(connectionFactoryMock.connect).not.toHaveBeenCalled();
  });
});
