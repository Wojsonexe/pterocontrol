import { ExecutionContext, UnauthorizedException } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { JwtService } from '@nestjs/jwt';
import { AuthenticatedUser, JwtAuthGuard } from './jwt-auth.guard';

describe('JwtAuthGuard', () => {
  const jwtServiceMock = { verifyAsync: jest.fn() };
  const reflectorMock = { getAllAndOverride: jest.fn() };
  let guard: JwtAuthGuard;

  function buildContext(headers: Record<string, string>, request?: { user?: AuthenticatedUser }): {
    context: ExecutionContext;
    request: { headers: Record<string, string>; user?: AuthenticatedUser };
  } {
    const req = { headers, ...request };
    const context = {
      switchToHttp: () => ({ getRequest: () => req }),
      getHandler: () => undefined,
      getClass: () => undefined,
    } as unknown as ExecutionContext;
    return { context, request: req };
  }

  beforeEach(() => {
    jwtServiceMock.verifyAsync.mockReset();
    reflectorMock.getAllAndOverride.mockReset();
    guard = new JwtAuthGuard(
      jwtServiceMock as unknown as JwtService,
      reflectorMock as unknown as Reflector,
    );
  });

  it('allows public routes without checking for a token', async () => {
    reflectorMock.getAllAndOverride.mockReturnValueOnce(true);
    const { context } = buildContext({});

    await expect(guard.canActivate(context)).resolves.toBe(true);
    expect(jwtServiceMock.verifyAsync).not.toHaveBeenCalled();
  });

  it('rejects a request with no Authorization header', async () => {
    reflectorMock.getAllAndOverride.mockReturnValueOnce(false);
    const { context } = buildContext({});

    await expect(guard.canActivate(context)).rejects.toThrow(
      UnauthorizedException,
    );
  });

  it('rejects a header that is not a Bearer token', async () => {
    reflectorMock.getAllAndOverride.mockReturnValueOnce(false);
    const { context } = buildContext({ authorization: 'Basic abc123' });

    await expect(guard.canActivate(context)).rejects.toThrow(
      UnauthorizedException,
    );
  });

  it('rejects an invalid or expired token', async () => {
    reflectorMock.getAllAndOverride.mockReturnValueOnce(false);
    jwtServiceMock.verifyAsync.mockRejectedValueOnce(new Error('expired'));
    const { context } = buildContext({ authorization: 'Bearer bad-token' });

    await expect(guard.canActivate(context)).rejects.toThrow(
      UnauthorizedException,
    );
  });

  it('attaches the decoded payload to the request and allows access', async () => {
    reflectorMock.getAllAndOverride.mockReturnValueOnce(false);
    const payload: AuthenticatedUser = {
      sub: 'u-1',
      email: 'dev@pterocontrol.local',
      tenantId: 't-1',
      role: 'owner',
    };
    jwtServiceMock.verifyAsync.mockResolvedValueOnce(payload);
    const { context, request } = buildContext({
      authorization: 'Bearer good-token',
    });

    await expect(guard.canActivate(context)).resolves.toBe(true);
    expect(request.user).toEqual(payload);
  });
});
