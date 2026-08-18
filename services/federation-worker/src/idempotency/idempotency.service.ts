import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';

const P2002_UNIQUE_CONSTRAINT_VIOLATION = 'P2002';

/**
 * At-least-once delivery (see MessageEnvelope doc comment in
 * @pterocontrol/rabbitmq) means the same jobId can be redelivered - a
 * worker crash after fully processing but before the ack reached the
 * broker, a nack-with-requeue, two worker instances racing on the same
 * message during a rebalance. ProcessedJob is the ledger that makes
 * redelivery safe: check before doing the side effect, record after.
 */
@Injectable()
export class IdempotencyService {
  constructor(private readonly prisma: PrismaService) {}

  async isProcessed(jobId: string): Promise<boolean> {
    const existing = await this.prisma.processedJob.findUnique({
      where: { jobId },
    });
    return existing !== null;
  }

  async markProcessed(
    jobId: string,
    jobType: string,
    tenantId: string,
  ): Promise<void> {
    try {
      await this.prisma.processedJob.create({
        data: { jobId, jobType, tenantId },
      });
    } catch (error) {
      // Two redeliveries processed concurrently both reaching here is a
      // real race, not a bug - the unique constraint on jobId is the
      // guard, and losing the race is a successful no-op, not an error.
      const isDuplicate =
        error instanceof Prisma.PrismaClientKnownRequestError &&
        error.code === P2002_UNIQUE_CONSTRAINT_VIOLATION;
      if (!isDuplicate) {
        throw error;
      }
    }
  }
}
