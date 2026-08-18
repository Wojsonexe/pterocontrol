import { ForbiddenException } from '@nestjs/common';
import { Test, TestingModule } from '@nestjs/testing';
import { JwtService } from '@nestjs/jwt';
import { TenantsService } from '../tenants/tenants.service';
import { UsersService } from '../users/users.service';
import { AuthService } from './auth.service';
import { PasswordService } from './password.service';

describe('AuthService', () => {
  let service: AuthService;
  const usersServiceMock = { findByEmail: jest.fn() };
  const passwordServiceMock = { verify: jest.fn(), hash: jest.fn() };
  const jwtServiceMock = { signAsync: jest.fn() };
  const tenantsServiceMock = { findPrimaryMembership: jest.fn() };
  const fakeUser = {
    id: 'u-1',
    email: 'dev@pterocontrol.local',
    passwordHash: 'hashed',
    createdAt: new Date('2026-01-01'),
  };

  beforeEach(async () => {
    usersServiceMock.findByEmail.mockReset();
    passwordServiceMock.verify.mockReset();
    jwtServiceMock.signAsync.mockReset();
    tenantsServiceMock.findPrimaryMembership.mockReset();

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        AuthService,
        { provide: UsersService, useValue: usersServiceMock },
        { provide: PasswordService, useValue: passwordServiceMock },
        { provide: JwtService, useValue: jwtServiceMock },
        { provide: TenantsService, useValue: tenantsServiceMock },
      ],
    }).compile();

    service = module.get<AuthService>(AuthService);
  });

  it('returns the safe user when credentials are valid', async () => {
    usersServiceMock.findByEmail.mockResolvedValueOnce(fakeUser);
    passwordServiceMock.verify.mockResolvedValueOnce(true);

    const result = await service.validateUser(
      'dev@pterocontrol.local',
      'correct-password',
    );

    expect(result).toEqual({
      id: 'u-1',
      email: 'dev@pterocontrol.local',
      createdAt: fakeUser.createdAt,
    });
  });

  it('returns null and never checks the password when the user does not exist', async () => {
    usersServiceMock.findByEmail.mockResolvedValueOnce(null);

    const result = await service.validateUser(
      'nobody@pterocontrol.local',
      'irrelevant',
    );

    expect(result).toBeNull();
    expect(passwordServiceMock.verify).not.toHaveBeenCalled();
  });

  it('returns null when the password is wrong', async () => {
    usersServiceMock.findByEmail.mockResolvedValueOnce(fakeUser);
    passwordServiceMock.verify.mockResolvedValueOnce(false);

    const result = await service.validateUser(
      'dev@pterocontrol.local',
      'wrong-password',
    );

    expect(result).toBeNull();
  });

  it('signs a JWT containing the user id, email, tenantId and role', async () => {
    tenantsServiceMock.findPrimaryMembership.mockResolvedValueOnce({
      tenantId: 't-1',
      role: 'owner',
    });
    jwtServiceMock.signAsync.mockResolvedValueOnce('signed.jwt.token');

    const result = await service.login({
      id: 'u-1',
      email: 'dev@pterocontrol.local',
      createdAt: new Date('2026-01-01'),
    });

    expect(result).toEqual({ accessToken: 'signed.jwt.token' });
    expect(jwtServiceMock.signAsync).toHaveBeenCalledWith({
      sub: 'u-1',
      email: 'dev@pterocontrol.local',
      tenantId: 't-1',
      role: 'owner',
    });
  });

  it('refuses to log in a user with no tenant membership', async () => {
    tenantsServiceMock.findPrimaryMembership.mockResolvedValueOnce(null);

    await expect(
      service.login({
        id: 'u-1',
        email: 'dev@pterocontrol.local',
        createdAt: new Date('2026-01-01'),
      }),
    ).rejects.toThrow(ForbiddenException);
    expect(jwtServiceMock.signAsync).not.toHaveBeenCalled();
  });
});
