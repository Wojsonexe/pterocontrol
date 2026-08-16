import { ConflictException, NotFoundException } from '@nestjs/common';
import { CredentialKind, InstanceStatus } from '@prisma/client';
import { PterodactylApplicationApiClient } from '../pterodactyl/pterodactyl-application-api.client';
import { PterodactylAuthError } from '../pterodactyl/pterodactyl-http.client';
import { SsrfValidatorService } from '../pterodactyl/ssrf-validator.service';
import { PrismaService } from '../prisma/prisma.service';
import { SecretsService } from '../secrets/secrets.service';
import { InstancesService } from './instances.service';

interface PrismaUpdateArgs {
  data: { status: InstanceStatus; lastError?: string | null; lastSyncedAt?: Date };
}

describe('InstancesService', () => {
  const prismaMock = {
    pterodactylInstance: {
      findUnique: jest.fn(),
      findFirst: jest.fn(),
      findMany: jest.fn(),
      delete: jest.fn(),
      update: jest.fn<Promise<unknown>, [PrismaUpdateArgs]>(),
    },
    instanceCredential: {
      findUnique: jest.fn(),
    },
    $transaction: jest.fn(),
  };
  const ssrfMock = { assertSafe: jest.fn() };
  const secretsMock = { encrypt: jest.fn(), decrypt: jest.fn() };
  const applicationApiMock = { testConnection: jest.fn() };

  let service: InstancesService;

  const dto = {
    name: 'EU-1',
    baseUrl: 'https://panel.eu1.example.com',
    applicationApiKey: 'ptla_key',
    clientApiKey: 'ptlc_key',
  };
  const tenantId = 't-1';

  beforeEach(() => {
    jest.clearAllMocks();
    service = new InstancesService(
      prismaMock as unknown as PrismaService,
      ssrfMock as unknown as SsrfValidatorService,
      secretsMock as unknown as SecretsService,
      applicationApiMock as unknown as PterodactylApplicationApiClient,
    );
  });

  describe('create', () => {
    it('runs SSRF validation before touching the database at all', async () => {
      ssrfMock.assertSafe.mockRejectedValueOnce(new Error('blocked: private IP'));

      await expect(service.create(tenantId, dto)).rejects.toThrow('blocked');
      expect(prismaMock.pterodactylInstance.findUnique).not.toHaveBeenCalled();
      expect(prismaMock.$transaction).not.toHaveBeenCalled();
    });

    it('rejects a duplicate (tenantId, baseUrl) with a 409', async () => {
      ssrfMock.assertSafe.mockResolvedValueOnce(undefined);
      prismaMock.pterodactylInstance.findUnique.mockResolvedValueOnce({
        id: 'existing',
      });

      await expect(service.create(tenantId, dto)).rejects.toThrow(
        ConflictException,
      );
      expect(prismaMock.$transaction).not.toHaveBeenCalled();
    });

    it('encrypts both keys, stores them, then marks ONLINE on a successful connectivity test', async () => {
      ssrfMock.assertSafe.mockResolvedValue(undefined);
      prismaMock.pterodactylInstance.findUnique.mockResolvedValueOnce(null);
      secretsMock.encrypt.mockImplementation((s: string) => Buffer.from(`enc(${s})`));

      const created = { id: 'inst-1', tenantId, name: dto.name, baseUrl: dto.baseUrl };
      const fakeTx = {
        pterodactylInstance: { create: jest.fn().mockResolvedValue(created) },
        instanceCredential: { create: jest.fn().mockResolvedValue({}) },
      };
      prismaMock.$transaction.mockImplementationOnce((fn: (tx: typeof fakeTx) => unknown) =>
        fn(fakeTx),
      );
      applicationApiMock.testConnection.mockResolvedValueOnce(undefined);
      prismaMock.pterodactylInstance.update.mockResolvedValueOnce({
        ...created,
        status: InstanceStatus.ONLINE,
      });

      const result = await service.create(tenantId, dto);

      expect(fakeTx.instanceCredential.create).toHaveBeenCalledWith({
        data: {
          instanceId: 'inst-1',
          kind: CredentialKind.APPLICATION_API_KEY,
          ciphertext: Uint8Array.from(Buffer.from('enc(ptla_key)')),
        },
      });
      expect(fakeTx.instanceCredential.create).toHaveBeenCalledWith({
        data: {
          instanceId: 'inst-1',
          kind: CredentialKind.CLIENT_API_KEY,
          ciphertext: Uint8Array.from(Buffer.from('enc(ptlc_key)')),
        },
      });
      expect(applicationApiMock.testConnection).toHaveBeenCalledWith(
        dto.baseUrl,
        dto.applicationApiKey,
      );
      const updateArgs = prismaMock.pterodactylInstance.update.mock.calls[0][0];
      expect(updateArgs.data.status).toBe(InstanceStatus.ONLINE);
      expect(result.status).toBe(InstanceStatus.ONLINE);
    });

    it('still saves the instance but marks UNREACHABLE with lastError when connectivity fails', async () => {
      ssrfMock.assertSafe.mockResolvedValue(undefined);
      prismaMock.pterodactylInstance.findUnique.mockResolvedValueOnce(null);
      secretsMock.encrypt.mockReturnValue(Buffer.from('enc'));

      const created = { id: 'inst-1', tenantId, name: dto.name, baseUrl: dto.baseUrl };
      const fakeTx = {
        pterodactylInstance: { create: jest.fn().mockResolvedValue(created) },
        instanceCredential: { create: jest.fn().mockResolvedValue({}) },
      };
      prismaMock.$transaction.mockImplementationOnce((fn: (tx: typeof fakeTx) => unknown) =>
        fn(fakeTx),
      );
      applicationApiMock.testConnection.mockRejectedValueOnce(
        new PterodactylAuthError('bad key'),
      );
      prismaMock.pterodactylInstance.update.mockResolvedValueOnce({
        ...created,
        status: InstanceStatus.UNREACHABLE,
        lastError: 'bad key',
      });

      const result = await service.create(tenantId, dto);

      const updateArgs = prismaMock.pterodactylInstance.update.mock.calls[0][0];
      expect(updateArgs.data.status).toBe(InstanceStatus.UNREACHABLE);
      expect(updateArgs.data.lastError).toBe('bad key');
      expect(result.status).toBe(InstanceStatus.UNREACHABLE);
    });
  });

  describe('tenant isolation', () => {
    it('findOneForTenant scopes the query by tenantId, not just id', async () => {
      prismaMock.pterodactylInstance.findFirst.mockResolvedValueOnce({
        id: 'inst-1',
        tenantId,
      });

      await service.findOneForTenant(tenantId, 'inst-1');

      expect(prismaMock.pterodactylInstance.findFirst).toHaveBeenCalledWith({
        where: { id: 'inst-1', tenantId },
      });
    });

    it('returns 404 (not 403) when the instance belongs to a different tenant', async () => {
      prismaMock.pterodactylInstance.findFirst.mockResolvedValueOnce(null);

      await expect(
        service.findOneForTenant('other-tenant', 'inst-1'),
      ).rejects.toThrow(NotFoundException);
    });

    it('findAllForTenant always filters by tenantId', async () => {
      prismaMock.pterodactylInstance.findMany.mockResolvedValueOnce([]);

      await service.findAllForTenant(tenantId);

      expect(prismaMock.pterodactylInstance.findMany).toHaveBeenCalledWith(
        expect.objectContaining({ where: { tenantId } }),
      );
    });

    it('remove() looks up via findOneForTenant before deleting (cannot delete across tenants)', async () => {
      prismaMock.pterodactylInstance.findFirst.mockResolvedValueOnce(null);

      await expect(service.remove('someone-elses-tenant', 'inst-1')).rejects.toThrow(
        NotFoundException,
      );
      expect(prismaMock.pterodactylInstance.delete).not.toHaveBeenCalled();
    });
  });

  describe('resync', () => {
    it('decrypts the stored Application API key and re-tests connectivity', async () => {
      prismaMock.pterodactylInstance.findFirst.mockResolvedValueOnce({
        id: 'inst-1',
        tenantId,
        baseUrl: dto.baseUrl,
      });
      prismaMock.instanceCredential.findUnique.mockResolvedValueOnce({
        ciphertext: Buffer.from('enc'),
      });
      secretsMock.decrypt.mockReturnValueOnce('decrypted-key');
      ssrfMock.assertSafe.mockResolvedValueOnce(undefined);
      applicationApiMock.testConnection.mockResolvedValueOnce(undefined);
      prismaMock.pterodactylInstance.update.mockResolvedValueOnce({
        id: 'inst-1',
        status: InstanceStatus.ONLINE,
      });

      await service.resync(tenantId, 'inst-1');

      expect(secretsMock.decrypt).toHaveBeenCalledWith(Buffer.from('enc'));
      expect(applicationApiMock.testConnection).toHaveBeenCalledWith(
        dto.baseUrl,
        'decrypted-key',
      );
    });
  });
});
