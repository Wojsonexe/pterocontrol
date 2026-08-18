import { BadGatewayException, BadRequestException, Injectable } from '@nestjs/common';
import {
  PterodactylBackupDto,
  PterodactylClientApiClient,
  PterodactylError,
} from '@pterocontrol/pterodactyl-sdk';
import { SecretsService } from '@pterocontrol/secrets';
import { CredentialKind } from '@prisma/client';
import { AuditService } from '../audit/audit.service';
import { InstancesService } from '../instances/instances.service';
import { PrismaService } from '../prisma/prisma.service';
import { ServersService } from '../servers/servers.service';
import { CreateBackupDto } from './dto/create-backup.dto';

/**
 * Thin, synchronous proxy to Pterodactyl's Client API backup endpoints -
 * same profile as ServersService.sendPowerAction()/getResources(): one
 * quick outbound call per operation, no RabbitMQ involved (Pterodactyl
 * itself schedules the actual backup work asynchronously on its side,
 * same as it does for power actions - see IMPLEMENTATION_STATUS.md for
 * why this is a deliberate architectural choice, not an oversight).
 * No local Backup cache table in this MVP - list is always fetched live.
 */
@Injectable()
export class BackupsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly instancesService: InstancesService,
    private readonly serversService: ServersService,
    private readonly secrets: SecretsService,
    private readonly clientApi: PterodactylClientApiClient,
    private readonly auditService: AuditService,
  ) {}

  async list(tenantId: string, serverId: string): Promise<PterodactylBackupDto[]> {
    const { baseUrl, apiKey, identifier } = await this.resolveServer(tenantId, serverId);
    try {
      return await this.clientApi.listBackups(baseUrl, apiKey, identifier);
    } catch (error) {
      throw this.toBadGateway(error, 'Could not list backups');
    }
  }

  async create(
    tenantId: string,
    actorId: string,
    serverId: string,
    dto: CreateBackupDto,
  ): Promise<PterodactylBackupDto> {
    const { baseUrl, apiKey, identifier } = await this.resolveServer(tenantId, serverId);
    try {
      const backup = await this.clientApi.createBackup(baseUrl, apiKey, identifier, {
        name: dto.name,
        ignored: dto.ignored,
        isLocked: dto.isLocked,
      });
      await this.auditService.record({
        tenantId,
        actorId,
        action: 'backup.create',
        targetType: 'server',
        targetId: serverId,
        result: 'success',
        metadata: { backupUuid: backup.uuid },
      });
      return backup;
    } catch (error) {
      await this.recordFailure(tenantId, actorId, 'backup.create', serverId, error);
      throw this.toBadGateway(error, 'Could not create backup');
    }
  }

  async getOne(
    tenantId: string,
    serverId: string,
    backupUuid: string,
  ): Promise<PterodactylBackupDto> {
    const { baseUrl, apiKey, identifier } = await this.resolveServer(tenantId, serverId);
    try {
      return await this.clientApi.getBackup(baseUrl, apiKey, identifier, backupUuid);
    } catch (error) {
      throw this.toBadGateway(error, 'Could not fetch backup');
    }
  }

  async getDownloadUrl(
    tenantId: string,
    serverId: string,
    backupUuid: string,
  ): Promise<{ url: string }> {
    const { baseUrl, apiKey, identifier } = await this.resolveServer(tenantId, serverId);
    try {
      const url = await this.clientApi.getBackupDownloadUrl(
        baseUrl,
        apiKey,
        identifier,
        backupUuid,
      );
      return { url };
    } catch (error) {
      throw this.toBadGateway(error, 'Could not get backup download url');
    }
  }

  async remove(
    tenantId: string,
    actorId: string,
    serverId: string,
    backupUuid: string,
  ): Promise<void> {
    const { baseUrl, apiKey, identifier } = await this.resolveServer(tenantId, serverId);
    try {
      await this.clientApi.deleteBackup(baseUrl, apiKey, identifier, backupUuid);
      await this.auditService.record({
        tenantId,
        actorId,
        action: 'backup.delete',
        targetType: 'server',
        targetId: serverId,
        result: 'success',
        metadata: { backupUuid },
      });
    } catch (error) {
      await this.recordFailure(tenantId, actorId, 'backup.delete', serverId, error, backupUuid);
      throw this.toBadGateway(error, 'Could not delete backup');
    }
  }

  async restore(
    tenantId: string,
    actorId: string,
    serverId: string,
    backupUuid: string,
    truncate: boolean,
  ): Promise<void> {
    const { baseUrl, apiKey, identifier } = await this.resolveServer(tenantId, serverId);
    try {
      await this.clientApi.restoreBackup(baseUrl, apiKey, identifier, backupUuid, truncate);
      await this.auditService.record({
        tenantId,
        actorId,
        action: 'backup.restore',
        targetType: 'server',
        targetId: serverId,
        result: 'success',
        metadata: { backupUuid, truncate },
      });
    } catch (error) {
      await this.recordFailure(tenantId, actorId, 'backup.restore', serverId, error, backupUuid);
      throw this.toBadGateway(error, 'Could not restore backup');
    }
  }

  async toggleLock(
    tenantId: string,
    actorId: string,
    serverId: string,
    backupUuid: string,
  ): Promise<PterodactylBackupDto> {
    const { baseUrl, apiKey, identifier } = await this.resolveServer(tenantId, serverId);
    try {
      const backup = await this.clientApi.toggleBackupLock(baseUrl, apiKey, identifier, backupUuid);
      await this.auditService.record({
        tenantId,
        actorId,
        action: 'backup.toggle_lock',
        targetType: 'server',
        targetId: serverId,
        result: 'success',
        metadata: { backupUuid, isLocked: backup.isLocked },
      });
      return backup;
    } catch (error) {
      await this.recordFailure(
        tenantId,
        actorId,
        'backup.toggle_lock',
        serverId,
        error,
        backupUuid,
      );
      throw this.toBadGateway(error, 'Could not toggle backup lock');
    }
  }

  private async resolveServer(
    tenantId: string,
    serverId: string,
  ): Promise<{ baseUrl: string; apiKey: string; identifier: string }> {
    const server = await this.serversService.findOneForTenant(tenantId, serverId);
    const instance = await this.instancesService.findOneForTenant(tenantId, server.instanceId);
    const apiKey = await this.getCredential(instance.id, CredentialKind.CLIENT_API_KEY);
    return { baseUrl: instance.baseUrl, apiKey, identifier: server.identifier };
  }

  private async getCredential(instanceId: string, kind: CredentialKind): Promise<string> {
    const credential = await this.prisma.instanceCredential.findUnique({
      where: { instanceId_kind: { instanceId, kind } },
    });
    if (!credential) {
      throw new BadRequestException(`Instance has no ${kind} credential configured`);
    }
    return this.secrets.decrypt(Buffer.from(credential.ciphertext));
  }

  private async recordFailure(
    tenantId: string,
    actorId: string,
    action: string,
    serverId: string,
    error: unknown,
    backupUuid?: string,
  ): Promise<void> {
    const message = error instanceof PterodactylError ? error.message : String(error);
    await this.auditService.record({
      tenantId,
      actorId,
      action,
      targetType: 'server',
      targetId: serverId,
      result: 'error',
      metadata: { message, ...(backupUuid ? { backupUuid } : {}) },
    });
  }

  private toBadGateway(error: unknown, prefix: string): BadGatewayException {
    const message = error instanceof PterodactylError ? error.message : String(error);
    return new BadGatewayException(`${prefix}: ${message}`);
  }
}
