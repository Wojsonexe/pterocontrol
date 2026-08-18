import { BadGatewayException } from '@nestjs/common';
import { PterodactylAuthError, PterodactylClientApiClient } from '@pterocontrol/pterodactyl-sdk';
import { AuditService } from '../audit/audit.service';
import { ServerCredentialResolverService } from '../servers/server-credential-resolver.service';
import { SchedulesService } from './schedules.service';

describe('SchedulesService', () => {
  const credentialsMock = { resolveClientApiCredential: jest.fn() };
  const clientApiMock = {
    listSchedules: jest.fn(),
    createSchedule: jest.fn(),
    getSchedule: jest.fn(),
    deleteSchedule: jest.fn(),
    createScheduleTask: jest.fn(),
    deleteScheduleTask: jest.fn(),
  };
  const auditServiceMock = {
    record: jest.fn<Promise<void>, [{ action: string; result: string }]>(),
  };

  let service: SchedulesService;
  const tenantId = 't-1';
  const actorId = 'actor-1';
  const resolved = { baseUrl: 'https://panel.example.com', apiKey: 'client-key', identifier: 'd3aac109' };

  beforeEach(() => {
    jest.clearAllMocks();
    service = new SchedulesService(
      credentialsMock as unknown as ServerCredentialResolverService,
      clientApiMock as unknown as PterodactylClientApiClient,
      auditServiceMock as unknown as AuditService,
    );
    credentialsMock.resolveClientApiCredential.mockResolvedValue(resolved);
  });

  describe('list', () => {
    it('maps a Pterodactyl-side failure to BadGatewayException', async () => {
      clientApiMock.listSchedules.mockRejectedValueOnce(new PterodactylAuthError('bad key'));

      await expect(service.list(tenantId, 'srv-1')).rejects.toThrow(BadGatewayException);
    });

    it('fetches using the resolved identifier', async () => {
      clientApiMock.listSchedules.mockResolvedValueOnce([]);

      await service.list(tenantId, 'srv-1');

      expect(clientApiMock.listSchedules).toHaveBeenCalledWith(
        resolved.baseUrl,
        resolved.apiKey,
        resolved.identifier,
      );
    });
  });

  describe('create', () => {
    it('records a success audit entry with the new schedule id', async () => {
      clientApiMock.createSchedule.mockResolvedValueOnce({ id: 5, name: 'Nightly' });

      await service.create(tenantId, actorId, 'srv-1', {
        name: 'Nightly',
        minute: '0',
        hour: '3',
        dayOfMonth: '*',
        month: '*',
        dayOfWeek: '*',
      });

      const auditArgs = auditServiceMock.record.mock.calls[0][0];
      expect(auditArgs.action).toBe('schedule.create');
      expect(auditArgs.result).toBe('success');
    });

    it('records a failure audit entry AND still throws on error', async () => {
      clientApiMock.createSchedule.mockRejectedValueOnce(new PterodactylAuthError('bad key'));

      await expect(
        service.create(tenantId, actorId, 'srv-1', {
          name: 'Nightly',
          minute: '0',
          hour: '3',
          dayOfMonth: '*',
          month: '*',
          dayOfWeek: '*',
        }),
      ).rejects.toThrow(BadGatewayException);

      const auditArgs = auditServiceMock.record.mock.calls[0][0];
      expect(auditArgs.result).toBe('error');
    });
  });

  describe('createTask / removeTask', () => {
    it('createTask records success with the schedule and task ids', async () => {
      clientApiMock.createScheduleTask.mockResolvedValueOnce({ id: 1, action: 'command' });

      await service.createTask(tenantId, actorId, 'srv-1', 5, {
        action: 'command',
        payload: 'say hi',
        timeOffset: 0,
      });

      expect(clientApiMock.createScheduleTask).toHaveBeenCalledWith(
        resolved.baseUrl,
        resolved.apiKey,
        resolved.identifier,
        5,
        { action: 'command', payload: 'say hi', timeOffset: 0 },
      );
      const auditArgs = auditServiceMock.record.mock.calls[0][0];
      expect(auditArgs.action).toBe('schedule.task.create');
    });

    it('removeTask calls deleteScheduleTask with both ids', async () => {
      clientApiMock.deleteScheduleTask.mockResolvedValueOnce(undefined);

      await service.removeTask(tenantId, actorId, 'srv-1', 5, 1);

      expect(clientApiMock.deleteScheduleTask).toHaveBeenCalledWith(
        resolved.baseUrl,
        resolved.apiKey,
        resolved.identifier,
        5,
        1,
      );
    });
  });
});
