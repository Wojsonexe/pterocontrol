import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { IdempotencyService } from './idempotency.service';

function uniqueConstraintError(): Prisma.PrismaClientKnownRequestError {
  return new Prisma.PrismaClientKnownRequestError('Unique constraint failed', {
    code: 'P2002',
    clientVersion: 'test',
  });
}

describe('IdempotencyService', () => {
  const prismaMock = {
    processedJob: { findUnique: jest.fn(), create: jest.fn() },
  };
  let service: IdempotencyService;

  beforeEach(() => {
    jest.clearAllMocks();
    service = new IdempotencyService(prismaMock as unknown as PrismaService);
  });

  describe('isProcessed', () => {
    it('returns false when no ProcessedJob row exists for this jobId', async () => {
      prismaMock.processedJob.findUnique.mockResolvedValueOnce(null);

      await expect(service.isProcessed('job-1')).resolves.toBe(false);
    });

    it('returns true when a ProcessedJob row already exists (redelivery)', async () => {
      prismaMock.processedJob.findUnique.mockResolvedValueOnce({ jobId: 'job-1' });

      await expect(service.isProcessed('job-1')).resolves.toBe(true);
    });
  });

  describe('markProcessed', () => {
    it('creates a ProcessedJob row with all fields', async () => {
      prismaMock.processedJob.create.mockResolvedValueOnce({});

      await service.markProcessed('job-1', 'federation.instance.sync', 't-1');

      expect(prismaMock.processedJob.create).toHaveBeenCalledWith({
        data: { jobId: 'job-1', jobType: 'federation.instance.sync', tenantId: 't-1' },
      });
    });

    it('silently succeeds (idempotent) on a concurrent duplicate insert (P2002)', async () => {
      prismaMock.processedJob.create.mockRejectedValueOnce(uniqueConstraintError());

      await expect(
        service.markProcessed('job-1', 'federation.instance.sync', 't-1'),
      ).resolves.toBeUndefined();
    });

    it('still throws for any other database error', async () => {
      prismaMock.processedJob.create.mockRejectedValueOnce(new Error('connection lost'));

      await expect(
        service.markProcessed('job-1', 'federation.instance.sync', 't-1'),
      ).rejects.toThrow('connection lost');
    });
  });
});
