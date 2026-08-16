import { BadGatewayException } from '@nestjs/common';
import { PterodactylAuthError, PterodactylClientApiClient } from '@pterocontrol/pterodactyl-sdk';
import { AuditService } from '../audit/audit.service';
import { ServerCredentialResolverService } from '../servers/server-credential-resolver.service';
import { AllocationsService } from './allocations.service';

describe('AllocationsService', () => {
  const credentialsMock = { resolveClientApiCredential: jest.fn() };
  const clientApiMock = {
    listAllocations: jest.fn(),
    createAllocation: jest.fn(),
    setAllocationNotes: jest.fn(),
    setPrimaryAllocation: jest.fn(),
    deleteAllocation: jest.fn(),
  };
  const auditServiceMock = {
    record: jest.fn<Promise<void>, [{ action: string; result: string }]>(),
  };

  let service: AllocationsService;
  const tenantId = 't-1';
  const actorId = 'actor-1';
  const resolved = { baseUrl: 'https://panel.example.com', apiKey: 'client-key', identifier: 'd3aac109' };

  beforeEach(() => {
    jest.clearAllMocks();
    service = new AllocationsService(
      credentialsMock as unknown as ServerCredentialResolverService,
      clientApiMock as unknown as PterodactylClientApiClient,
      auditServiceMock as unknown as AuditService,
    );
    credentialsMock.resolveClientApiCredential.mockResolvedValue(resolved);
  });

  it('list maps a Pterodactyl-side failure to BadGatewayException', async () => {
    clientApiMock.listAllocations.mockRejectedValueOnce(new PterodactylAuthError('bad key'));

    await expect(service.list(tenantId, 'srv-1')).rejects.toThrow(BadGatewayException);
  });

  it('create records a success audit entry', async () => {
    clientApiMock.createAllocation.mockResolvedValueOnce({ id: 1, port: 25566 });

    await service.create(tenantId, actorId, 'srv-1');

    const auditArgs = auditServiceMock.record.mock.calls[0][0];
    expect(auditArgs.action).toBe('allocation.create');
    expect(auditArgs.result).toBe('success');
  });

  it('setNotes passes notes through and records the audit entry', async () => {
    clientApiMock.setAllocationNotes.mockResolvedValueOnce({ id: 1, notes: 'lobby' });

    await service.setNotes(tenantId, actorId, 'srv-1', 1, 'lobby');

    expect(clientApiMock.setAllocationNotes).toHaveBeenCalledWith(
      resolved.baseUrl,
      resolved.apiKey,
      resolved.identifier,
      1,
      'lobby',
    );
  });

  it('setPrimary records success and failure audit entries appropriately', async () => {
    clientApiMock.setPrimaryAllocation.mockRejectedValueOnce(new PterodactylAuthError('bad key'));

    await expect(service.setPrimary(tenantId, actorId, 'srv-1', 1)).rejects.toThrow(
      BadGatewayException,
    );

    const auditArgs = auditServiceMock.record.mock.calls[0][0];
    expect(auditArgs.result).toBe('error');
  });

  it('remove calls deleteAllocation with the resolved server identifier', async () => {
    clientApiMock.deleteAllocation.mockResolvedValueOnce(undefined);

    await service.remove(tenantId, actorId, 'srv-1', 1);

    expect(clientApiMock.deleteAllocation).toHaveBeenCalledWith(
      resolved.baseUrl,
      resolved.apiKey,
      resolved.identifier,
      1,
    );
  });
});
