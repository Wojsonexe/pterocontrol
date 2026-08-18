import { Injectable } from '@nestjs/common';
import { Event, Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';

export interface EventEntry {
  tenantId: string;
  instanceId?: string;
  serverId?: string;
  type: string;
  payload: Record<string, unknown>;
  dedupKey: string;
}

export interface EventFilters {
  instanceId?: string;
  serverId?: string;
  type?: string;
}

const P2002_UNIQUE_CONSTRAINT_VIOLATION = 'P2002';

/**
 * "What happened" (system-observed state changes), distinct from
 * AuditLog ("who did what" - operator-initiated actions). See schema.prisma.
 */
@Injectable()
export class EventsService {
  constructor(private readonly prisma: PrismaService) {}

  async record(entry: EventEntry): Promise<void> {
    try {
      await this.prisma.event.create({
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
      // Unique constraint violation on dedupKey: this exact event was
      // already recorded - idempotency working as intended, not a real
      // error. Anything else still propagates.
      const isDuplicateEvent =
        error instanceof Prisma.PrismaClientKnownRequestError &&
        error.code === P2002_UNIQUE_CONSTRAINT_VIOLATION;
      if (!isDuplicateEvent) {
        throw error;
      }
    }
  }

  findAllForTenant(tenantId: string, filters: EventFilters): Promise<Event[]> {
    return this.prisma.event.findMany({
      where: {
        tenantId,
        ...(filters.instanceId ? { instanceId: filters.instanceId } : {}),
        ...(filters.serverId ? { serverId: filters.serverId } : {}),
        ...(filters.type ? { type: filters.type } : {}),
      },
      orderBy: { occurredAt: 'desc' },
      take: 100,
    });
  }
}
