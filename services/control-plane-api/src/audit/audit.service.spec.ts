import { PrismaService } from '../prisma/prisma.service';
import { AuditService } from './audit.service';

interface AuditCreateArgs {
  data: {
    tenantId: string;
    actorId?: string;
    action: string;
    targetType: string;
    targetId?: string;
    result: string;
    metadata?: unknown;
  };
}

describe('AuditService', () => {
  const prismaMock = { auditLog: { create: jest.fn<Promise<unknown>, [AuditCreateArgs]>() } };
  let service: AuditService;

  beforeEach(() => {
    prismaMock.auditLog.create.mockReset();
    service = new AuditService(prismaMock as unknown as PrismaService);
  });

  it('writes every field through to the AuditLog table', async () => {
    await service.record({
      tenantId: 't-1',
      actorId: 'u-1',
      action: 'power.restart',
      targetType: 'server',
      targetId: 'srv-1',
      result: 'success',
      metadata: { signal: 'restart' },
    });

    expect(prismaMock.auditLog.create).toHaveBeenCalledWith({
      data: {
        tenantId: 't-1',
        actorId: 'u-1',
        action: 'power.restart',
        targetType: 'server',
        targetId: 'srv-1',
        result: 'success',
        metadata: { signal: 'restart' },
      },
    });
  });

  it('records failures too, not just successes', async () => {
    await service.record({
      tenantId: 't-1',
      action: 'power.kill',
      targetType: 'server',
      result: 'error',
      metadata: { message: 'instance unreachable' },
    });

    const callArgs = prismaMock.auditLog.create.mock.calls[0][0];
    expect(callArgs.data.result).toBe('error');
  });
});
