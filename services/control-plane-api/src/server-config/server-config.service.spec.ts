import { BadGatewayException, BadRequestException, NotFoundException } from '@nestjs/common';
import { PterodactylAuthError, PterodactylClientApiClient } from '@pterocontrol/pterodactyl-sdk';
import { SecretsService } from '@pterocontrol/secrets';
import { AuditService } from '../audit/audit.service';
import { InstancesService } from '../instances/instances.service';
import { PrismaService } from '../prisma/prisma.service';
import { ServersService } from '../servers/servers.service';
import { ServerConfigService } from './server-config.service';

describe('ServerConfigService', () => {
  const prismaMock = { instanceCredential: { findUnique: jest.fn() } };
  const instancesServiceMock = { findOneForTenant: jest.fn() };
  const serversServiceMock = { findOneForTenant: jest.fn() };
  const secretsMock = { decrypt: jest.fn() };
  const clientApiMock = {
    getStartupVariables: jest.fn(),
    updateStartupVariable: jest.fn(),
  };
  const auditServiceMock = {
    record: jest.fn<Promise<void>, [{ result: string }]>(),
  };

  let service: ServerConfigService;
  const tenantId = 't-1';
  const actorId = 'actor-1';
  const server = { id: 'srv-1', tenantId, instanceId: 'inst-1', identifier: 'd3aac109' };
  const instance = { id: 'inst-1', tenantId, baseUrl: 'https://panel.example.com' };

  const variables = [
    {
      name: 'Server Jar File',
      description: 'jar',
      envVariable: 'SERVER_JARFILE',
      defaultValue: 'server.jar',
      serverValue: 'paper.jar',
      isEditable: true,
      rules: 'required|string',
    },
    {
      name: 'Server Port',
      description: 'port',
      envVariable: 'SERVER_PORT',
      defaultValue: '25565',
      serverValue: '25565',
      isEditable: false,
      rules: 'required|integer',
    },
  ];

  beforeEach(() => {
    jest.clearAllMocks();
    service = new ServerConfigService(
      prismaMock as unknown as PrismaService,
      instancesServiceMock as unknown as InstancesService,
      serversServiceMock as unknown as ServersService,
      secretsMock as unknown as SecretsService,
      clientApiMock as unknown as PterodactylClientApiClient,
      auditServiceMock as unknown as AuditService,
    );
    serversServiceMock.findOneForTenant.mockResolvedValue(server);
    instancesServiceMock.findOneForTenant.mockResolvedValue(instance);
    prismaMock.instanceCredential.findUnique.mockResolvedValue({
      ciphertext: Buffer.from('enc'),
    });
    secretsMock.decrypt.mockReturnValue('client-key');
  });

  describe('getStartupVariables', () => {
    it('never calls Pterodactyl for a server in another tenant', async () => {
      serversServiceMock.findOneForTenant.mockRejectedValueOnce(
        new NotFoundException('Server not found'),
      );

      await expect(service.getStartupVariables('other-tenant', 'srv-1')).rejects.toThrow(
        NotFoundException,
      );
      expect(clientApiMock.getStartupVariables).not.toHaveBeenCalled();
    });

    it('fetches variables using the server identifier', async () => {
      clientApiMock.getStartupVariables.mockResolvedValueOnce(variables);

      const result = await service.getStartupVariables(tenantId, 'srv-1');

      expect(result).toEqual(variables);
      expect(clientApiMock.getStartupVariables).toHaveBeenCalledWith(
        instance.baseUrl,
        'client-key',
        'd3aac109',
      );
    });

    it('maps a Pterodactyl-side failure to BadGatewayException', async () => {
      clientApiMock.getStartupVariables.mockRejectedValueOnce(
        new PterodactylAuthError('bad key'),
      );

      await expect(service.getStartupVariables(tenantId, 'srv-1')).rejects.toThrow(
        BadGatewayException,
      );
    });
  });

  describe('updateStartupVariable', () => {
    it('rejects an unknown variable key without calling the update endpoint', async () => {
      clientApiMock.getStartupVariables.mockResolvedValueOnce(variables);

      await expect(
        service.updateStartupVariable(tenantId, actorId, 'srv-1', {
          key: 'NOT_A_REAL_VAR',
          value: 'x',
        }),
      ).rejects.toThrow(BadRequestException);
      expect(clientApiMock.updateStartupVariable).not.toHaveBeenCalled();
    });

    it('rejects a non-editable variable without calling the update endpoint', async () => {
      clientApiMock.getStartupVariables.mockResolvedValueOnce(variables);

      await expect(
        service.updateStartupVariable(tenantId, actorId, 'srv-1', {
          key: 'SERVER_PORT',
          value: '25566',
        }),
      ).rejects.toThrow(BadRequestException);
      expect(clientApiMock.updateStartupVariable).not.toHaveBeenCalled();
    });

    it('updates an editable variable and records a success audit entry', async () => {
      clientApiMock.getStartupVariables.mockResolvedValueOnce(variables);
      clientApiMock.updateStartupVariable.mockResolvedValueOnce({
        ...variables[0],
        serverValue: 'paper-new.jar',
      });

      const result = await service.updateStartupVariable(tenantId, actorId, 'srv-1', {
        key: 'SERVER_JARFILE',
        value: 'paper-new.jar',
      });

      expect(result.serverValue).toBe('paper-new.jar');
      expect(clientApiMock.updateStartupVariable).toHaveBeenCalledWith(
        instance.baseUrl,
        'client-key',
        'd3aac109',
        'SERVER_JARFILE',
        'paper-new.jar',
      );
      const auditArgs = auditServiceMock.record.mock.calls[0][0];
      expect(auditArgs.result).toBe('success');
    });

    it('records a failure audit entry AND still throws when the Pterodactyl update fails', async () => {
      clientApiMock.getStartupVariables.mockResolvedValueOnce(variables);
      clientApiMock.updateStartupVariable.mockRejectedValueOnce(
        new PterodactylAuthError('bad key'),
      );

      await expect(
        service.updateStartupVariable(tenantId, actorId, 'srv-1', {
          key: 'SERVER_JARFILE',
          value: 'paper-new.jar',
        }),
      ).rejects.toThrow(BadGatewayException);

      const auditArgs = auditServiceMock.record.mock.calls[0][0];
      expect(auditArgs.result).toBe('error');
    });
  });
});
