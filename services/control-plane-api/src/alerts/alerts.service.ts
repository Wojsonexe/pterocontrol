import { BadRequestException, Injectable, Logger, NotFoundException } from '@nestjs/common';
import {
  Alert,
  AlertMetric,
  AlertOperator,
  AlertRule,
  InstanceStatus,
  Prisma,
} from '@prisma/client';
import { InstancesService } from '../instances/instances.service';
import { NotificationsService } from '../notifications/notifications.service';
import { PrismaService } from '../prisma/prisma.service';
import { ServersService } from '../servers/servers.service';
import { CreateAlertRuleDto } from './dto/create-alert-rule.dto';

// A server with no ResourceSnapshot at all in this long, or none ever
// recorded, is treated as offline - matches the collection cadence
// (ResourceCollectionScheduler runs every minute, see servers module);
// 5 minutes gives it room for a couple of missed/slow collection ticks
// before alerting, not just one.
const SERVER_STALE_THRESHOLD_MS = 5 * 60 * 1000;

export interface AlertFilters {
  ruleId?: string;
  serverId?: string;
  instanceId?: string;
  active?: boolean;
}

const THRESHOLD_METRICS: AlertMetric[] = [
  AlertMetric.CPU_PERCENT,
  AlertMetric.MEMORY_BYTES,
  AlertMetric.DISK_BYTES,
];

/**
 * Reads ResourceSnapshot/PterodactylInstance.status (never anything
 * live from Pterodactyl itself - the evaluator only ever looks at what's
 * already in Postgres, source of truth per the RabbitMQ mandate) and
 * turns AlertRule definitions into Alert rows. One rule watches exactly
 * one resource (no tenant-wide wildcard rules in this MVP - see
 * IMPLEMENTATION_STATUS.md); dedup/cooldown is keyed on (ruleId,
 * resourceId) so the same still-active condition never creates a second
 * open Alert, and a resolved one can't immediately re-fire before its
 * cooldown elapses.
 */
@Injectable()
export class AlertsService {
  private readonly logger = new Logger(AlertsService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly instancesService: InstancesService,
    private readonly serversService: ServersService,
    private readonly notificationsService: NotificationsService,
  ) {}

  async createRule(tenantId: string, dto: CreateAlertRuleDto): Promise<AlertRule> {
    if (THRESHOLD_METRICS.includes(dto.metric)) {
      if (!dto.serverId) {
        throw new BadRequestException(`serverId is required for metric ${dto.metric}`);
      }
      if (dto.operator === undefined || dto.threshold === undefined) {
        throw new BadRequestException(
          `operator and threshold are required for metric ${dto.metric}`,
        );
      }
      await this.serversService.findOneForTenant(tenantId, dto.serverId); // tenant-ownership check
    } else if (dto.metric === AlertMetric.SERVER_OFFLINE) {
      if (!dto.serverId) {
        throw new BadRequestException('serverId is required for metric SERVER_OFFLINE');
      }
      await this.serversService.findOneForTenant(tenantId, dto.serverId);
    } else if (dto.metric === AlertMetric.INSTANCE_OFFLINE) {
      if (!dto.instanceId) {
        throw new BadRequestException('instanceId is required for metric INSTANCE_OFFLINE');
      }
      await this.instancesService.findOneForTenant(tenantId, dto.instanceId);
    }

    return this.prisma.alertRule.create({
      data: {
        tenantId,
        name: dto.name,
        metric: dto.metric,
        operator: dto.operator,
        threshold: dto.threshold,
        serverId: dto.serverId,
        instanceId: dto.instanceId,
        cooldownSeconds: dto.cooldownSeconds ?? 300,
      },
    });
  }

  findAllRulesForTenant(tenantId: string): Promise<AlertRule[]> {
    return this.prisma.alertRule.findMany({
      where: { tenantId },
      orderBy: { createdAt: 'asc' },
    });
  }

  async removeRule(tenantId: string, id: string): Promise<void> {
    const rule = await this.prisma.alertRule.findFirst({ where: { id, tenantId } });
    if (!rule) {
      throw new NotFoundException('Alert rule not found');
    }
    await this.prisma.alertRule.delete({ where: { id: rule.id } });
  }

  findAllAlertsForTenant(tenantId: string, filters: AlertFilters): Promise<Alert[]> {
    return this.prisma.alert.findMany({
      where: {
        tenantId,
        ...(filters.ruleId ? { ruleId: filters.ruleId } : {}),
        ...(filters.serverId ? { resourceId: filters.serverId } : {}),
        ...(filters.instanceId ? { resourceId: filters.instanceId } : {}),
        ...(filters.active !== undefined
          ? { resolvedAt: filters.active ? null : { not: null } }
          : {}),
      },
      orderBy: { triggeredAt: 'desc' },
      take: 200,
    });
  }

  /**
   * Runs for every enabled rule across every tenant in one pass (called
   * by AlertEvaluationScheduler, see that file for the cadence). One
   * rule failing to evaluate (e.g. its server was deleted after the rule
   * was created) is caught and logged per-rule, never allowed to abort
   * the whole sweep - same "one instance's failure must never stop the
   * whole worker" principle as federation-worker's job handlers.
   */
  async evaluate(): Promise<void> {
    const rules = await this.prisma.alertRule.findMany({ where: { enabled: true } });
    for (const rule of rules) {
      try {
        await this.evaluateRule(rule);
      } catch (error) {
        this.logger.warn(
          `Alert rule ${rule.id} (tenant ${rule.tenantId}) failed to evaluate: ${String(error)}`,
        );
      }
    }
  }

  private async evaluateRule(rule: AlertRule): Promise<void> {
    if (THRESHOLD_METRICS.includes(rule.metric)) {
      await this.evaluateThresholdRule(rule);
    } else if (rule.metric === AlertMetric.SERVER_OFFLINE) {
      await this.evaluateServerOfflineRule(rule);
    } else if (rule.metric === AlertMetric.INSTANCE_OFFLINE) {
      await this.evaluateInstanceOfflineRule(rule);
    }
  }

  private async evaluateThresholdRule(rule: AlertRule): Promise<void> {
    if (!rule.serverId || rule.threshold === null || rule.operator === null) {
      return; // malformed rule (should not happen via createRule) - skip, not crash
    }

    const snapshot = await this.prisma.resourceSnapshot.findFirst({
      where: { serverId: rule.serverId },
      orderBy: { observedAt: 'desc' },
    });
    if (!snapshot) {
      return; // nothing collected for this server yet
    }

    let observedValue: number;
    switch (rule.metric) {
      case AlertMetric.CPU_PERCENT:
        observedValue = snapshot.cpuAbsolutePercent ?? 0;
        break;
      case AlertMetric.MEMORY_BYTES:
        observedValue = Number(snapshot.memoryBytes ?? 0n);
        break;
      case AlertMetric.DISK_BYTES:
        observedValue = Number(snapshot.diskBytes ?? 0n);
        break;
      default:
        return;
    }

    const conditionMet =
      rule.operator === AlertOperator.GREATER_THAN
        ? observedValue > rule.threshold
        : observedValue < rule.threshold;

    await this.applyEvaluation(rule, rule.serverId, conditionMet, {
      metric: rule.metric,
      operator: rule.operator,
      threshold: rule.threshold,
      observedValue,
    });
  }

  private async evaluateServerOfflineRule(rule: AlertRule): Promise<void> {
    if (!rule.serverId) {
      return;
    }
    const snapshot = await this.prisma.resourceSnapshot.findFirst({
      where: { serverId: rule.serverId },
      orderBy: { observedAt: 'desc' },
    });
    const conditionMet =
      !snapshot || Date.now() - snapshot.observedAt.getTime() > SERVER_STALE_THRESHOLD_MS;

    await this.applyEvaluation(rule, rule.serverId, conditionMet, {
      metric: rule.metric,
      lastObservedAt: snapshot?.observedAt ?? null,
    });
  }

  private async evaluateInstanceOfflineRule(rule: AlertRule): Promise<void> {
    if (!rule.instanceId) {
      return;
    }
    const instance = await this.prisma.pterodactylInstance.findUnique({
      where: { id: rule.instanceId },
      select: { status: true },
    });
    const conditionMet = !instance || instance.status === InstanceStatus.UNREACHABLE;

    await this.applyEvaluation(rule, rule.instanceId, conditionMet, {
      metric: rule.metric,
      status: instance?.status ?? null,
    });
  }

  private async applyEvaluation(
    rule: AlertRule,
    resourceId: string,
    conditionMet: boolean,
    payload: Record<string, unknown>,
  ): Promise<void> {
    const activeAlert = await this.prisma.alert.findFirst({
      where: { ruleId: rule.id, resourceId, resolvedAt: null },
    });

    if (!conditionMet) {
      if (activeAlert) {
        await this.prisma.alert.update({
          where: { id: activeAlert.id },
          data: { resolvedAt: new Date() },
        });
      }
      return;
    }

    if (activeAlert) {
      return; // already alerting on this exact (rule, resource) - no duplicate
    }

    const lastAlert = await this.prisma.alert.findFirst({
      where: { ruleId: rule.id, resourceId },
      orderBy: { triggeredAt: 'desc' },
    });
    if (lastAlert?.resolvedAt) {
      const cooldownMs = rule.cooldownSeconds * 1000;
      if (Date.now() - lastAlert.resolvedAt.getTime() < cooldownMs) {
        return; // still within cooldown since it last resolved
      }
    }

    const alert = await this.prisma.alert.create({
      data: {
        tenantId: rule.tenantId,
        ruleId: rule.id,
        resourceId,
        payload: payload as Prisma.InputJsonValue,
      },
    });

    // Fire-and-log, not fire-and-forget-silently: a channel failing to
    // queue must never undo the Alert this method just committed (see
    // NotificationsService.notifyAlertTriggered's own doc comment).
    await this.notificationsService.notifyAlertTriggered(rule.tenantId, alert.id);
  }
}
