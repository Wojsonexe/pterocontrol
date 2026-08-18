import { ForbiddenException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../prisma/prisma.service';
import { TenantsService } from './tenants.service';

describe('TenantsService.bootstrap', () => {
  const configMock = { get: jest.fn() };
  const passwordServiceMock = { hash: jest.fn(), verify: jest.fn() };
  const prismaMock = { $transaction: jest.fn() };
  let service: TenantsService;

  const dto = {
    tenantName: 'Acme',
    ownerEmail: 'owner@acme.test',
    ownerPassword: 'a-long-enough-password',
  };

  beforeEach(() => {
    configMock.get.mockReset();
    passwordServiceMock.hash.mockReset();
    prismaMock.$transaction.mockReset();

    service = new TenantsService(
      prismaMock as unknown as PrismaService,
      passwordServiceMock,
      configMock as unknown as ConfigService,
    );
  });

  it('rejects when BOOTSTRAP_TOKEN is not configured at all', async () => {
    configMock.get.mockReturnValueOnce(undefined);

    await expect(service.bootstrap('any-token', dto)).rejects.toThrow(
      ForbiddenException,
    );
    expect(prismaMock.$transaction).not.toHaveBeenCalled();
    expect(passwordServiceMock.hash).not.toHaveBeenCalled();
  });

  it('rejects when the provided token does not match', async () => {
    configMock.get.mockReturnValueOnce('correct-token');

    await expect(service.bootstrap('wrong-token', dto)).rejects.toThrow(
      ForbiddenException,
    );
    expect(prismaMock.$transaction).not.toHaveBeenCalled();
  });

  it('rejects when no token is provided at all', async () => {
    configMock.get.mockReturnValueOnce('correct-token');

    await expect(service.bootstrap(undefined, dto)).rejects.toThrow(
      ForbiddenException,
    );
  });

  it('hashes the password and runs tenant+role+user+membership creation inside one transaction', async () => {
    configMock.get.mockReturnValueOnce('correct-token');
    passwordServiceMock.hash.mockResolvedValueOnce('hashed-password');

    const fakeTx = {
      tenant: { create: jest.fn().mockResolvedValue({ id: 't-1', name: dto.tenantName }) },
      role: { upsert: jest.fn().mockResolvedValue({ id: 'r-1', name: 'owner' }) },
      user: { create: jest.fn().mockResolvedValue({ id: 'u-1', email: dto.ownerEmail }) },
      membership: { create: jest.fn().mockResolvedValue({ id: 'm-1' }) },
    };
    prismaMock.$transaction.mockImplementationOnce(
      (fn: (tx: typeof fakeTx) => unknown) => fn(fakeTx),
    );

    const result = await service.bootstrap('correct-token', dto);

    expect(passwordServiceMock.hash).toHaveBeenCalledWith(dto.ownerPassword);
    expect(fakeTx.tenant.create).toHaveBeenCalledWith({
      data: { name: dto.tenantName },
    });
    expect(fakeTx.role.upsert).toHaveBeenCalledWith(
      expect.objectContaining({ where: { name: 'owner' } }),
    );
    expect(fakeTx.user.create).toHaveBeenCalledWith({
      data: { email: dto.ownerEmail, passwordHash: 'hashed-password' },
    });
    expect(fakeTx.membership.create).toHaveBeenCalledWith({
      data: { tenantId: 't-1', userId: 'u-1', roleId: 'r-1' },
    });
    expect(result).toEqual({
      tenant: { id: 't-1', name: dto.tenantName },
      owner: { id: 'u-1', email: dto.ownerEmail },
    });
  });
});
