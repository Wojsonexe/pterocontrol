import { BadGatewayException, Injectable } from '@nestjs/common';
import {
  PterodactylClientApiClient,
  PterodactylError,
  PterodactylServerDatabaseDto,
} from '@pterocontrol/pterodactyl-sdk';
import { AuditService } from '../audit/audit.service';
import { ServerCredentialResolverService } from '../servers/server-credential-resolver.service';
import { CreateServerDatabaseDto } from './dto/create-server-database.dto';
import { ServerDatabaseCredentialService } from './server-database-credential.service';

/**
 * Per-server MySQL databases provisioned through Pterodactyl's own
 * database host - distinct from Database Gateway (direct SQL execution,
 * ../database-gateway), which this service feeds: create() and
 * rotatePassword() are the only two moments Pterodactyl ever returns the
 * plaintext password, so both persist it (encrypted) via
 * ServerDatabaseCredentialService for the Gateway to use later. Otherwise
 * same synchronous-proxy profile as Backups/Schedules/Allocations.
 * Credentials (the generated password) are never written to AuditLog
 * metadata - only the database id/name are, same "no secrets in logs"
 * posture as SecretsService/InstanceCredential.
 */
@Injectable()
export class ServerDatabasesService {
  constructor(
    private readonly credentials: ServerCredentialResolverService,
    private readonly clientApi: PterodactylClientApiClient,
    private readonly auditService: AuditService,
    private readonly credentialStore: ServerDatabaseCredentialService,
  ) {}

  async list(tenantId: string, serverId: string): Promise<PterodactylServerDatabaseDto[]> {
    const { baseUrl, apiKey, identifier } = await this.credentials.resolveClientApiCredential(
      tenantId,
      serverId,
    );
    try {
      return await this.clientApi.listServerDatabases(baseUrl, apiKey, identifier);
    } catch (error) {
      throw this.toBadGateway(error, 'Could not list databases');
    }
  }

  async create(
    tenantId: string,
    actorId: string,
    serverId: string,
    dto: CreateServerDatabaseDto,
  ): Promise<PterodactylServerDatabaseDto> {
    const { baseUrl, apiKey, identifier } = await this.credentials.resolveClientApiCredential(
      tenantId,
      serverId,
    );
    try {
      const database = await this.clientApi.createServerDatabase(
        baseUrl,
        apiKey,
        identifier,
        dto.database,
        dto.remote,
      );
      await this.auditService.record({
        tenantId,
        actorId,
        action: 'server_database.create',
        targetType: 'server',
        targetId: serverId,
        result: 'success',
        metadata: { databaseId: database.id, name: database.name },
      });
      await this.credentialStore.upsert(tenantId, serverId, database);
      return database;
    } catch (error) {
      await this.recordFailure(tenantId, actorId, 'server_database.create', serverId, error);
      throw this.toBadGateway(error, 'Could not create database');
    }
  }

  async rotatePassword(
    tenantId: string,
    actorId: string,
    serverId: string,
    databaseId: string,
  ): Promise<PterodactylServerDatabaseDto> {
    const { baseUrl, apiKey, identifier } = await this.credentials.resolveClientApiCredential(
      tenantId,
      serverId,
    );
    try {
      const database = await this.clientApi.rotateServerDatabasePassword(
        baseUrl,
        apiKey,
        identifier,
        databaseId,
      );
      await this.auditService.record({
        tenantId,
        actorId,
        action: 'server_database.rotate_password',
        targetType: 'server',
        targetId: serverId,
        result: 'success',
        metadata: { databaseId },
      });
      await this.credentialStore.upsert(tenantId, serverId, database);
      return database;
    } catch (error) {
      await this.recordFailure(
        tenantId,
        actorId,
        'server_database.rotate_password',
        serverId,
        error,
        databaseId,
      );
      throw this.toBadGateway(error, 'Could not rotate database password');
    }
  }

  async remove(
    tenantId: string,
    actorId: string,
    serverId: string,
    databaseId: string,
  ): Promise<void> {
    const { baseUrl, apiKey, identifier } = await this.credentials.resolveClientApiCredential(
      tenantId,
      serverId,
    );
    try {
      await this.clientApi.deleteServerDatabase(baseUrl, apiKey, identifier, databaseId);
      await this.auditService.record({
        tenantId,
        actorId,
        action: 'server_database.delete',
        targetType: 'server',
        targetId: serverId,
        result: 'success',
        metadata: { databaseId },
      });
      await this.credentialStore.remove(serverId, databaseId);
    } catch (error) {
      await this.recordFailure(
        tenantId,
        actorId,
        'server_database.delete',
        serverId,
        error,
        databaseId,
      );
      throw this.toBadGateway(error, 'Could not delete database');
    }
  }

  private async recordFailure(
    tenantId: string,
    actorId: string,
    action: string,
    serverId: string,
    error: unknown,
    databaseId?: string,
  ): Promise<void> {
    const message = error instanceof PterodactylError ? error.message : String(error);
    await this.auditService.record({
      tenantId,
      actorId,
      action,
      targetType: 'server',
      targetId: serverId,
      result: 'error',
      metadata: { message, ...(databaseId !== undefined ? { databaseId } : {}) },
    });
  }

  private toBadGateway(error: unknown, prefix: string): BadGatewayException {
    const message = error instanceof PterodactylError ? error.message : String(error);
    return new BadGatewayException(`${prefix}: ${message}`);
  }
}
