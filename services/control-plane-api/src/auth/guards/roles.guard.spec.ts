import { ExecutionContext, ForbiddenException } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { AuthenticatedUser } from './jwt-auth.guard';
import { RolesGuard } from './roles.guard';

describe('RolesGuard', () => {
  const reflectorMock = { getAllAndOverride: jest.fn() };
  let guard: RolesGuard;

  function buildContext(user?: AuthenticatedUser): ExecutionContext {
    return {
      switchToHttp: () => ({ getRequest: () => ({ user }) }),
      getHandler: () => undefined,
      getClass: () => undefined,
    } as unknown as ExecutionContext;
  }

  const owner: AuthenticatedUser = {
    sub: 'u-1',
    email: 'a@b.com',
    tenantId: 't-1',
    role: 'owner',
  };

  beforeEach(() => {
    reflectorMock.getAllAndOverride.mockReset();
    guard = new RolesGuard(reflectorMock as unknown as Reflector);
  });

  it('allows access when the route requires no specific role', () => {
    reflectorMock.getAllAndOverride.mockReturnValueOnce(undefined);
    expect(guard.canActivate(buildContext({ ...owner, role: 'viewer' }))).toBe(
      true,
    );
  });

  it('allows access when the user role is in the required list', () => {
    reflectorMock.getAllAndOverride.mockReturnValueOnce(['owner', 'admin']);
    expect(guard.canActivate(buildContext(owner))).toBe(true);
  });

  it('denies access when the user role is not in the required list', () => {
    reflectorMock.getAllAndOverride.mockReturnValueOnce(['owner']);
    expect(() =>
      guard.canActivate(buildContext({ ...owner, role: 'viewer' })),
    ).toThrow(ForbiddenException);
  });

  it('denies access when there is no authenticated user at all', () => {
    reflectorMock.getAllAndOverride.mockReturnValueOnce(['owner']);
    expect(() => guard.canActivate(buildContext(undefined))).toThrow(
      ForbiddenException,
    );
  });
});
