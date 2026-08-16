import { BadGatewayException, Injectable } from '@nestjs/common';
import {
  PterodactylClientApiClient,
  PterodactylError,
  PterodactylScheduleDto,
  PterodactylScheduleTaskDto,
} from '@pterocontrol/pterodactyl-sdk';
import { AuditService } from '../audit/audit.service';
import { ServerCredentialResolverService } from '../servers/server-credential-resolver.service';
import { CreateScheduleTaskDto } from './dto/create-schedule-task.dto';
import { CreateScheduleDto } from './dto/create-schedule.dto';

/**
 * Same synchronous-proxy profile as Backups/Server Configuration - see
 * those modules' own doc comments for the full rationale and the API-
 * contract-provenance caveat that applies here too (confirmed via direct
 * Flutter code search: no schedules/tasks REST wiring exists there).
 */
@Injectable()
export class SchedulesService {
  constructor(
    private readonly credentials: ServerCredentialResolverService,
    private readonly clientApi: PterodactylClientApiClient,
    private readonly auditService: AuditService,
  ) {}

  async list(tenantId: string, serverId: string): Promise<PterodactylScheduleDto[]> {
    const { baseUrl, apiKey, identifier } = await this.credentials.resolveClientApiCredential(
      tenantId,
      serverId,
    );
    try {
      return await this.clientApi.listSchedules(baseUrl, apiKey, identifier);
    } catch (error) {
      throw this.toBadGateway(error, 'Could not list schedules');
    }
  }

  async create(
    tenantId: string,
    actorId: string,
    serverId: string,
    dto: CreateScheduleDto,
  ): Promise<PterodactylScheduleDto> {
    const { baseUrl, apiKey, identifier } = await this.credentials.resolveClientApiCredential(
      tenantId,
      serverId,
    );
    try {
      const schedule = await this.clientApi.createSchedule(baseUrl, apiKey, identifier, dto);
      await this.auditService.record({
        tenantId,
        actorId,
        action: 'schedule.create',
        targetType: 'server',
        targetId: serverId,
        result: 'success',
        metadata: { scheduleId: schedule.id, name: schedule.name },
      });
      return schedule;
    } catch (error) {
      await this.recordFailure(tenantId, actorId, 'schedule.create', serverId, error);
      throw this.toBadGateway(error, 'Could not create schedule');
    }
  }

  async getOne(
    tenantId: string,
    serverId: string,
    scheduleId: number,
  ): Promise<PterodactylScheduleDto> {
    const { baseUrl, apiKey, identifier } = await this.credentials.resolveClientApiCredential(
      tenantId,
      serverId,
    );
    try {
      return await this.clientApi.getSchedule(baseUrl, apiKey, identifier, scheduleId);
    } catch (error) {
      throw this.toBadGateway(error, 'Could not fetch schedule');
    }
  }

  async remove(
    tenantId: string,
    actorId: string,
    serverId: string,
    scheduleId: number,
  ): Promise<void> {
    const { baseUrl, apiKey, identifier } = await this.credentials.resolveClientApiCredential(
      tenantId,
      serverId,
    );
    try {
      await this.clientApi.deleteSchedule(baseUrl, apiKey, identifier, scheduleId);
      await this.auditService.record({
        tenantId,
        actorId,
        action: 'schedule.delete',
        targetType: 'server',
        targetId: serverId,
        result: 'success',
        metadata: { scheduleId },
      });
    } catch (error) {
      await this.recordFailure(tenantId, actorId, 'schedule.delete', serverId, error, scheduleId);
      throw this.toBadGateway(error, 'Could not delete schedule');
    }
  }

  async createTask(
    tenantId: string,
    actorId: string,
    serverId: string,
    scheduleId: number,
    dto: CreateScheduleTaskDto,
  ): Promise<PterodactylScheduleTaskDto> {
    const { baseUrl, apiKey, identifier } = await this.credentials.resolveClientApiCredential(
      tenantId,
      serverId,
    );
    try {
      const task = await this.clientApi.createScheduleTask(
        baseUrl,
        apiKey,
        identifier,
        scheduleId,
        dto,
      );
      await this.auditService.record({
        tenantId,
        actorId,
        action: 'schedule.task.create',
        targetType: 'server',
        targetId: serverId,
        result: 'success',
        metadata: { scheduleId, taskId: task.id, action: task.action },
      });
      return task;
    } catch (error) {
      await this.recordFailure(
        tenantId,
        actorId,
        'schedule.task.create',
        serverId,
        error,
        scheduleId,
      );
      throw this.toBadGateway(error, 'Could not create schedule task');
    }
  }

  async removeTask(
    tenantId: string,
    actorId: string,
    serverId: string,
    scheduleId: number,
    taskId: number,
  ): Promise<void> {
    const { baseUrl, apiKey, identifier } = await this.credentials.resolveClientApiCredential(
      tenantId,
      serverId,
    );
    try {
      await this.clientApi.deleteScheduleTask(baseUrl, apiKey, identifier, scheduleId, taskId);
      await this.auditService.record({
        tenantId,
        actorId,
        action: 'schedule.task.delete',
        targetType: 'server',
        targetId: serverId,
        result: 'success',
        metadata: { scheduleId, taskId },
      });
    } catch (error) {
      await this.recordFailure(
        tenantId,
        actorId,
        'schedule.task.delete',
        serverId,
        error,
        scheduleId,
      );
      throw this.toBadGateway(error, 'Could not delete schedule task');
    }
  }

  private async recordFailure(
    tenantId: string,
    actorId: string,
    action: string,
    serverId: string,
    error: unknown,
    scheduleId?: number,
  ): Promise<void> {
    const message = error instanceof PterodactylError ? error.message : String(error);
    await this.auditService.record({
      tenantId,
      actorId,
      action,
      targetType: 'server',
      targetId: serverId,
      result: 'error',
      metadata: { message, ...(scheduleId !== undefined ? { scheduleId } : {}) },
    });
  }

  private toBadGateway(error: unknown, prefix: string): BadGatewayException {
    const message = error instanceof PterodactylError ? error.message : String(error);
    return new BadGatewayException(`${prefix}: ${message}`);
  }
}
