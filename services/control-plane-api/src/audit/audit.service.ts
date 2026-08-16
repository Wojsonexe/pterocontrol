import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';

export interface AuditEntry {
  tenantId: string;
  actorId?: string;
  action: string;
  targetType: string;
  targetId?: string;
  result: 'success' | 'denied' | 'error';
  metadata?: Record<string, unknown>;
}

/**
 * Append-only audit trail. Every privileged action writes exactly one
 * row here regardless of outcome (success AND failure/denial are both
 * recorded) - see AuditLog's own doc comment in schema.prisma.
 */
@Injectable()
export class AuditService {
  constructor(private readonly prisma: PrismaService) {}

  async record(entry: AuditEntry): Promise<void> {
    await this.prisma.auditLog.create({
      data: {
        tenantId: entry.tenantId,
        actorId: entry.actorId,
        action: entry.action,
        targetType: entry.targetType,
        targetId: entry.targetId,
        result: entry.result,
        metadata: entry.metadata as Prisma.InputJsonValue | undefined,
      },
    });
  }
}
