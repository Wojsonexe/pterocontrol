import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { EventsService } from './events.service';

function uniqueConstraintError(): Prisma.PrismaClientKnownRequestError {
  return new Prisma.PrismaClientKnownRequestError('Unique constraint failed', {
    code: 'P2002',
    clientVersion: 'test',
  });
}

describe('EventsService', () => {
  const prismaMock = {
    event: { create: jest.fn(), findMany: jest.fn() },
  };
  let service: EventsService;

  beforeEach(() => {
    jest.clearAllMocks();
    service = new EventsService(prismaMock as unknown as PrismaService);
  });

  describe('record', () => {
    it('creates a row with all fields passed through', async () => {
      prismaMock.event.create.mockResolvedValueOnce({});

      await service.record({
        tenantId: 't-1',
        instanceId: 'inst-1',
        type: 'instance_status_changed',
        payload: { from: 'PENDING_SYNC', to: 'ONLINE' },
        dedupKey: 'dedup-1',
      });

      expect(prismaMock.event.create).toHaveBeenCalledWith({
        data: {
          tenantId: 't-1',
          instanceId: 'inst-1',
          serverId: undefined,
          type: 'instance_status_changed',
          payload: { from: 'PENDING_SYNC', to: 'ONLINE' },
          dedupKey: 'dedup-1',
        },
      });
    });

    it('silently succeeds (idempotent) when the dedupKey already exists (P2002)', async () => {
      prismaMock.event.create.mockRejectedValueOnce(uniqueConstraintError());

      await expect(
        service.record({
          tenantId: 't-1',
          type: 'server_created',
          payload: {},
          dedupKey: 'dup',
        }),
      ).resolves.toBeUndefined();
    });

    it('still throws for any other database error', async () => {
      prismaMock.event.create.mockRejectedValueOnce(new Error('connection lost'));

      await expect(
        service.record({
          tenantId: 't-1',
          type: 'server_created',
          payload: {},
          dedupKey: 'x',
        }),
      ).rejects.toThrow('connection lost');
    });
  });

  describe('findAllForTenant', () => {
    it('always scopes by tenantId and applies optional filters', async () => {
      prismaMock.event.findMany.mockResolvedValueOnce([]);

      await service.findAllForTenant('t-1', { instanceId: 'inst-1', type: 'server_created' });

      expect(prismaMock.event.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { tenantId: 't-1', instanceId: 'inst-1', type: 'server_created' },
        }),
      );
    });
  });
});
