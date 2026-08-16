import { NotFoundException } from '@nestjs/common';
import { PterodactylServerDatabaseDto } from '@pterocontrol/pterodactyl-sdk';
import { SecretsService } from '@pterocontrol/secrets';
import { PrismaService } from '../prisma/prisma.service';
import { ServerDatabaseCredentialService } from './server-database-credential.service';

describe('ServerDatabaseCredentialService', () => {
  const prismaMock = {
    serverDatabaseCredential: {
      upsert: jest.fn(),
      deleteMany: jest.fn(),
      findFirst: jest.fn(),
    },
  };
  const secretsMock = {
    encrypt: jest.fn<Buffer, [string]>(),
    decrypt: jest.fn<string, [Buffer]>(),
  };

  let service: ServerDatabaseCredentialService;

  beforeEach(() => {
    jest.clearAllMocks();
    service = new ServerDatabaseCredentialService(
      prismaMock as unknown as PrismaService,
      secretsMock as unknown as SecretsService,
    );
  });

  describe('upsert', () => {
    it('encrypts the password and upserts by (serverId, pterodactylDatabaseId)', async () => {
      const database: PterodactylServerDatabaseDto = {
        id: 'db-1',
        host: '10.0.0.5',
        port: 3306,
        name: 's1_survival',
        username: 'u1_survival',
        connectionsFrom: '%',
        maxConnections: 0,
        password: 'plaintext-password',
      };
      secretsMock.encrypt.mockReturnValueOnce(Buffer.from('encrypted'));

      await service.upsert('t-1', 'srv-1', database);

      expect(secretsMock.encrypt).toHaveBeenCalledWith('plaintext-password');
      expect(prismaMock.serverDatabaseCredential.upsert).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { serverId_pterodactylDatabaseId: { serverId: 'srv-1', pterodactylDatabaseId: 'db-1' } },
        }),
      );
    });

    it('does nothing when Pterodactyl did not return a password (e.g. plain list read)', async () => {
      const database: PterodactylServerDatabaseDto = {
        id: 'db-1',
        host: '10.0.0.5',
        port: 3306,
        name: 's1_survival',
        username: 'u1_survival',
        connectionsFrom: '%',
        maxConnections: 0,
        password: null,
      };

      await service.upsert('t-1', 'srv-1', database);

      expect(secretsMock.encrypt).not.toHaveBeenCalled();
      expect(prismaMock.serverDatabaseCredential.upsert).not.toHaveBeenCalled();
    });
  });

  it('remove deletes by (serverId, pterodactylDatabaseId)', async () => {
    await service.remove('srv-1', 'db-1');

    expect(prismaMock.serverDatabaseCredential.deleteMany).toHaveBeenCalledWith({
      where: { serverId: 'srv-1', pterodactylDatabaseId: 'db-1' },
    });
  });

  describe('resolve', () => {
    it('throws NotFoundException when no credential row is scoped to this tenant/server/database', async () => {
      prismaMock.serverDatabaseCredential.findFirst.mockResolvedValueOnce(null);

      await expect(service.resolve('t-1', 'srv-1', 'db-1')).rejects.toThrow(NotFoundException);
    });

    it('decrypts and returns the stored connection details, scoped by tenantId+serverId+databaseId', async () => {
      prismaMock.serverDatabaseCredential.findFirst.mockResolvedValueOnce({
        host: '10.0.0.5',
        port: 3306,
        databaseName: 's1_survival',
        username: 'u1_survival',
        ciphertext: Buffer.from('encrypted'),
      });
      secretsMock.decrypt.mockReturnValueOnce('plaintext-password');

      const result = await service.resolve('t-1', 'srv-1', 'db-1');

      expect(prismaMock.serverDatabaseCredential.findFirst).toHaveBeenCalledWith({
        where: { tenantId: 't-1', serverId: 'srv-1', pterodactylDatabaseId: 'db-1' },
      });
      expect(result).toEqual({
        host: '10.0.0.5',
        port: 3306,
        databaseName: 's1_survival',
        username: 'u1_survival',
        password: 'plaintext-password',
      });
    });
  });
});
