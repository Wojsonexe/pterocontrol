import { BadRequestException, NotFoundException } from '@nestjs/common';
import { AlertMetric, AlertOperator, InstanceStatus } from '@prisma/client';
import { InstancesService } from '../instances/instances.service';
import { NotificationsService } from '../notifications/notifications.service';
import { PrismaService } from '../prisma/prisma.service';
import { ServersService } from '../servers/servers.service';
import { AlertsService } from './alerts.service';

interface AlertRuleCreateArgs {
  data: { tenantId: string; cooldownSeconds: number };
}

interface AlertCreateArgs {
  data: { tenantId: string; ruleId: string; resourceId: string };
}

describe('AlertsService', () => {
  const prismaMock = {
    alertRule: {
      create: jest.fn<Promise<unknown>, [AlertRuleCreateArgs]>(),
      findMany: jest.fn(),
      findFirst: jest.fn(),
      delete: jest.fn(),
    },
    alert: {
      findFirst: jest.fn(),
      findMany: jest.fn(),
      create: jest.fn<Promise<unknown>, [AlertCreateArgs]>(),
      update: jest.fn(),
    },
    resourceSnapshot: { findFirst: jest.fn() },
    pterodactylInstance: { findUnique: jest.fn() },
  };
  const instancesServiceMock = { findOneForTenant: jest.fn() };
  const serversServiceMock = { findOneForTenant: jest.fn() };
  const notificationsServiceMock = { notifyAlertTriggered: jest.fn() };

  let service: AlertsService;
  const tenantId = 't-1';

  beforeEach(() => {
    jest.clearAllMocks();
    notificationsServiceMock.notifyAlertTriggered.mockResolvedValue(undefined);
    service = new AlertsService(
      prismaMock as unknown as PrismaService,
      instancesServiceMock as unknown as InstancesService,
      serversServiceMock as unknown as ServersService,
      notificationsServiceMock as unknown as NotificationsService,
    );
  });

  describe('createRule', () => {
    it('rejects a threshold metric (CPU_PERCENT) without serverId', async () => {
      await expect(
        service.createRule(tenantId, { name: 'x', metric: AlertMetric.CPU_PERCENT }),
      ).rejects.toThrow(BadRequestException);
    });

    it('rejects a threshold metric without operator/threshold', async () => {
      await expect(
        service.createRule(tenantId, {
          name: 'x',
          metric: AlertMetric.CPU_PERCENT,
          serverId: 'srv-1',
        }),
      ).rejects.toThrow(BadRequestException);
    });

    it('checks server tenant-ownership before creating a server-scoped rule', async () => {
      serversServiceMock.findOneForTenant.mockRejectedValueOnce(
        new NotFoundException('Server not found'),
      );

      await expect(
        service.createRule(tenantId, {
          name: 'x',
          metric: AlertMetric.CPU_PERCENT,
          serverId: 'not-mine',
          operator: AlertOperator.GREATER_THAN,
          threshold: 90,
        }),
      ).rejects.toThrow(NotFoundException);
      expect(prismaMock.alertRule.create).not.toHaveBeenCalled();
    });

    it('rejects INSTANCE_OFFLINE without instanceId', async () => {
      await expect(
        service.createRule(tenantId, { name: 'x', metric: AlertMetric.INSTANCE_OFFLINE }),
      ).rejects.toThrow(BadRequestException);
    });

    it('checks instance tenant-ownership before creating an instance-scoped rule', async () => {
      instancesServiceMock.findOneForTenant.mockRejectedValueOnce(
        new NotFoundException('Instance not found'),
      );

      await expect(
        service.createRule(tenantId, {
          name: 'x',
          metric: AlertMetric.INSTANCE_OFFLINE,
          instanceId: 'not-mine',
        }),
      ).rejects.toThrow(NotFoundException);
    });

    it('creates a valid threshold rule with a default cooldown', async () => {
      serversServiceMock.findOneForTenant.mockResolvedValueOnce({ id: 'srv-1', tenantId });
      prismaMock.alertRule.create.mockResolvedValueOnce({ id: 'rule-1' });

      await service.createRule(tenantId, {
        name: 'High CPU',
        metric: AlertMetric.CPU_PERCENT,
        serverId: 'srv-1',
        operator: AlertOperator.GREATER_THAN,
        threshold: 90,
      });

      const createArgs = prismaMock.alertRule.create.mock.calls[0][0];
      expect(createArgs.data.tenantId).toBe(tenantId);
      expect(createArgs.data.cooldownSeconds).toBe(300);
    });
  });

  describe('removeRule', () => {
    it('404s when the rule belongs to another tenant', async () => {
      prismaMock.alertRule.findFirst.mockResolvedValueOnce(null);

      await expect(service.removeRule('other-tenant', 'rule-1')).rejects.toThrow(
        NotFoundException,
      );
      expect(prismaMock.alertRule.delete).not.toHaveBeenCalled();
    });
  });

  describe('evaluate - CPU_PERCENT threshold rule', () => {
    const rule = {
      id: 'rule-1',
      tenantId,
      metric: AlertMetric.CPU_PERCENT,
      operator: AlertOperator.GREATER_THAN,
      threshold: 90,
      serverId: 'srv-1',
      instanceId: null,
      cooldownSeconds: 300,
      enabled: true,
    };

    it('creates a new Alert when the threshold is exceeded and none is active', async () => {
      prismaMock.alertRule.findMany.mockResolvedValueOnce([rule]);
      prismaMock.resourceSnapshot.findFirst.mockResolvedValueOnce({
        cpuAbsolutePercent: 95,
        observedAt: new Date(),
      });
      prismaMock.alert.findFirst.mockResolvedValueOnce(null); // no active alert
      prismaMock.alert.create.mockResolvedValueOnce({ id: 'alert-1' });

      await service.evaluate();

      const createArgs = prismaMock.alert.create.mock.calls[0][0];
      expect(createArgs.data.tenantId).toBe(tenantId);
      expect(createArgs.data.ruleId).toBe('rule-1');
      expect(createArgs.data.resourceId).toBe('srv-1');
      expect(notificationsServiceMock.notifyAlertTriggered).toHaveBeenCalledWith(
        tenantId,
        'alert-1',
      );
    });

    it('does not create a duplicate Alert when one is already active for this (rule, resource)', async () => {
      prismaMock.alertRule.findMany.mockResolvedValueOnce([rule]);
      prismaMock.resourceSnapshot.findFirst.mockResolvedValueOnce({
        cpuAbsolutePercent: 95,
        observedAt: new Date(),
      });
      prismaMock.alert.findFirst.mockResolvedValueOnce({ id: 'alert-1', resolvedAt: null });

      await service.evaluate();

      expect(prismaMock.alert.create).not.toHaveBeenCalled();
      expect(notificationsServiceMock.notifyAlertTriggered).not.toHaveBeenCalled();
    });

    it('resolves the active Alert once the value drops back under the threshold, without notifying', async () => {
      prismaMock.alertRule.findMany.mockResolvedValueOnce([rule]);
      prismaMock.resourceSnapshot.findFirst.mockResolvedValueOnce({
        cpuAbsolutePercent: 10,
        observedAt: new Date(),
      });
      prismaMock.alert.findFirst.mockResolvedValueOnce({ id: 'alert-1', resolvedAt: null });
      prismaMock.alert.update.mockResolvedValueOnce({});

      await service.evaluate();

      expect(prismaMock.alert.update).toHaveBeenCalledWith({
        where: { id: 'alert-1' },
        data: { resolvedAt: expect.any(Date) as Date },
      });
      expect(notificationsServiceMock.notifyAlertTriggered).not.toHaveBeenCalled();
    });

    it('respects the cooldown - does not re-alert immediately after a resolved Alert', async () => {
      prismaMock.alertRule.findMany.mockResolvedValueOnce([rule]);
      prismaMock.resourceSnapshot.findFirst.mockResolvedValueOnce({
        cpuAbsolutePercent: 95,
        observedAt: new Date(),
      });
      prismaMock.alert.findFirst
        .mockResolvedValueOnce(null) // no active alert
        .mockResolvedValueOnce({
          id: 'alert-0',
          resolvedAt: new Date(), // resolved just now - well within a 300s cooldown
        });

      await service.evaluate();

      expect(prismaMock.alert.create).not.toHaveBeenCalled();
    });

    it('re-alerts once the cooldown window has fully elapsed', async () => {
      prismaMock.alertRule.findMany.mockResolvedValueOnce([rule]);
      prismaMock.resourceSnapshot.findFirst.mockResolvedValueOnce({
        cpuAbsolutePercent: 95,
        observedAt: new Date(),
      });
      prismaMock.alert.findFirst
        .mockResolvedValueOnce(null)
        .mockResolvedValueOnce({
          id: 'alert-0',
          resolvedAt: new Date(Date.now() - 10 * 60 * 1000), // resolved 10 min ago, cooldown is 300s
        });
      prismaMock.alert.create.mockResolvedValueOnce({});

      await service.evaluate();

      expect(prismaMock.alert.create).toHaveBeenCalled();
    });

    it('skips evaluation entirely when there is no ResourceSnapshot yet', async () => {
      prismaMock.alertRule.findMany.mockResolvedValueOnce([rule]);
      prismaMock.resourceSnapshot.findFirst.mockResolvedValueOnce(null);

      await service.evaluate();

      expect(prismaMock.alert.findFirst).not.toHaveBeenCalled();
      expect(prismaMock.alert.create).not.toHaveBeenCalled();
    });

    it('one rule throwing does not stop the rest of the sweep', async () => {
      const brokenRule = { ...rule, id: 'rule-broken' };
      const healthyRule = { ...rule, id: 'rule-healthy' };
      prismaMock.alertRule.findMany.mockResolvedValueOnce([brokenRule, healthyRule]);
      prismaMock.resourceSnapshot.findFirst
        .mockRejectedValueOnce(new Error('DB hiccup'))
        .mockResolvedValueOnce({ cpuAbsolutePercent: 95, observedAt: new Date() });
      prismaMock.alert.findFirst.mockResolvedValueOnce(null);
      prismaMock.alert.create.mockResolvedValueOnce({});

      await expect(service.evaluate()).resolves.toBeUndefined();
      expect(prismaMock.alert.create).toHaveBeenCalledTimes(1);
    });
  });

  describe('evaluate - SERVER_OFFLINE rule', () => {
    const rule = {
      id: 'rule-2',
      tenantId,
      metric: AlertMetric.SERVER_OFFLINE,
      operator: null,
      threshold: null,
      serverId: 'srv-1',
      instanceId: null,
      cooldownSeconds: 300,
      enabled: true,
    };

    it('fires when there is no snapshot at all', async () => {
      prismaMock.alertRule.findMany.mockResolvedValueOnce([rule]);
      prismaMock.resourceSnapshot.findFirst.mockResolvedValueOnce(null);
      prismaMock.alert.findFirst.mockResolvedValueOnce(null);
      prismaMock.alert.create.mockResolvedValueOnce({});

      await service.evaluate();

      expect(prismaMock.alert.create).toHaveBeenCalled();
    });

    it('fires when the latest snapshot is older than the stale threshold', async () => {
      prismaMock.alertRule.findMany.mockResolvedValueOnce([rule]);
      prismaMock.resourceSnapshot.findFirst.mockResolvedValueOnce({
        observedAt: new Date(Date.now() - 10 * 60 * 1000),
      });
      prismaMock.alert.findFirst.mockResolvedValueOnce(null);
      prismaMock.alert.create.mockResolvedValueOnce({});

      await service.evaluate();

      expect(prismaMock.alert.create).toHaveBeenCalled();
    });

    it('does not fire when the latest snapshot is fresh', async () => {
      prismaMock.alertRule.findMany.mockResolvedValueOnce([rule]);
      prismaMock.resourceSnapshot.findFirst.mockResolvedValueOnce({
        observedAt: new Date(),
      });
      prismaMock.alert.findFirst.mockResolvedValueOnce(null);

      await service.evaluate();

      expect(prismaMock.alert.create).not.toHaveBeenCalled();
    });
  });

  describe('evaluate - INSTANCE_OFFLINE rule', () => {
    const rule = {
      id: 'rule-3',
      tenantId,
      metric: AlertMetric.INSTANCE_OFFLINE,
      operator: null,
      threshold: null,
      serverId: null,
      instanceId: 'inst-1',
      cooldownSeconds: 300,
      enabled: true,
    };

    it('fires when the instance status is UNREACHABLE', async () => {
      prismaMock.alertRule.findMany.mockResolvedValueOnce([rule]);
      prismaMock.pterodactylInstance.findUnique.mockResolvedValueOnce({
        status: InstanceStatus.UNREACHABLE,
      });
      prismaMock.alert.findFirst.mockResolvedValueOnce(null);
      prismaMock.alert.create.mockResolvedValueOnce({});

      await service.evaluate();

      const createArgs = prismaMock.alert.create.mock.calls[0][0];
      expect(createArgs.data.ruleId).toBe('rule-3');
      expect(createArgs.data.resourceId).toBe('inst-1');
    });

    it('does not fire when the instance is ONLINE', async () => {
      prismaMock.alertRule.findMany.mockResolvedValueOnce([rule]);
      prismaMock.pterodactylInstance.findUnique.mockResolvedValueOnce({
        status: InstanceStatus.ONLINE,
      });
      prismaMock.alert.findFirst.mockResolvedValueOnce(null);

      await service.evaluate();

      expect(prismaMock.alert.create).not.toHaveBeenCalled();
    });
  });

  describe('findAllAlertsForTenant', () => {
    it('always scopes by tenantId and applies active/resolved filter', async () => {
      prismaMock.alert.findMany.mockResolvedValueOnce([]);

      await service.findAllAlertsForTenant(tenantId, { active: true });

      expect(prismaMock.alert.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { tenantId, resolvedAt: null },
        }),
      );
    });
  });
});
