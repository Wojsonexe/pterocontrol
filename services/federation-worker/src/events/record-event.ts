import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';

const P2002_UNIQUE_CONSTRAINT_VIOLATION = 'P2002';

export interface EventEntry {
  tenantId: string;
  instanceId?: string;
  serverId?: string;
  type: string;
  payload: Record<string, unknown>;
  dedupKey: string;
}

/**
 * Same dedup-by-unique-constraint pattern as control-plane-api's
 * EventsService.record() - duplicated here deliberately rather than
 * extracted into a shared package: it is ~15 lines of a single Prisma
 * write with a P2002 catch, not security-critical (unlike the SSRF/
 * secrets extractions), and extracting it would require restructuring
 * how PrismaService is injected across two separate NestJS apps for
 * little real benefit. See IMPLEMENTATION_STATUS.md FAZA 9b for this
 * scope decision.
 */
export async function recordEvent(
  prisma: PrismaService,
  entry: EventEntry,
): Promise<void> {
  try {
    await prisma.event.create({
      data: {
        tenantId: entry.tenantId,
        instanceId: entry.instanceId,
        serverId: entry.serverId,
        type: entry.type,
        payload: entry.payload as Prisma.InputJsonValue,
        dedupKey: entry.dedupKey,
      },
    });
  } catch (error) {
    const isDuplicateEvent =
      error instanceof Prisma.PrismaClientKnownRequestError &&
      error.code === P2002_UNIQUE_CONSTRAINT_VIOLATION;
    if (!isDuplicateEvent) {
      throw error;
    }
  }
}
