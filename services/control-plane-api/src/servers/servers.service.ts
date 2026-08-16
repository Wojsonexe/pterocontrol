import {
  BadGatewayException,
  BadRequestException,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import { CredentialKind, Server } from '@prisma/client';
import { AuditService } from '../audit/audit.service';
import { InstancesService } from '../instances/instances.service';
import { PterodactylApplicationApiClient } from '../pterodactyl/pterodactyl-application-api.client';
import {
  PterodactylClientApiClient,
  PterodactylPowerSignal,
  PterodactylResourceUsageDto,
} from '../pterodactyl/pterodactyl-client-api.client';
import { PterodactylError } from '../pterodactyl/pterodactyl-http.client';
import { PrismaService } from '../prisma/prisma.service';
import { SecretsService } from '../secrets/secrets.service';

export interface ServerFilters {
  instanceId?: string;
  q?: string;
}

export interface SyncResult {
  synced: number;
}

/**
 * Global server model: aggregates Server rows across every
 * PterodactylInstance a tenant owns, synced on-demand (via
 * syncInstance()) from the Application API's server inventory. No
 * background/scheduled polling yet (BullMQ worker) - see
 * IMPLEMENTATION_STATUS.md; this is the synchronous half of FAZA 3's
 * "server synchronization" requirement. Also owns live resources/power
 * actions (Client API, FAZA 6) - a different credential than the
 * Application API key used for inventory sync.
 */
@Injectable()
export class ServersService {
  private readonly logger = new Logger(ServersService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly instancesService: InstancesService,
    private readonly secrets: SecretsService,
    private readonly applicationApi: PterodactylApplicationApiClient,
    private readonly clientApi: PterodactylClientApiClient,
    private readonly auditService: AuditService,
  ) {}

  async syncInstance(tenantId: string, instanceId: string): Promise<SyncResult> {
    const instance = await this.instancesService.findOneForTenant(tenantId, instanceId);
    const apiKey = await this.getCredential(instance.id, CredentialKind.APPLICATION_API_KEY);

    let remoteServers: Awaited<ReturnType<PterodactylApplicationApiClient['listServers']>>;
    try {
      remoteServers = await this.applicationApi.listServers(instance.baseUrl, apiKey);
    } catch (error) {
      // A Pterodactyl-side failure (unreachable, bad key, unexpected
      // response) must surface as a clean, expected HttpException - not
      // fall through to AllExceptionsFilter's generic "Internal server
      // error" 500, which is reserved for genuine bugs, not "the remote
      // panel didn't answer".
      const message = error instanceof PterodactylError ? error.message : String(error);
      this.logger.warn(
        `Server sync failed for instance ${instance.id} (tenant ${tenantId}): ${message}`,
      );
      throw new BadGatewayException(`Could not sync servers from instance: ${message}`);
    }

    for (const remote of remoteServers) {
      // Mapping local -> global: (instanceId, pterodactylUuid) is the
      // natural key, never the bare Pterodactyl numeric id (not unique
      // across independent installs) - matches docs/architecture §2.
      await this.prisma.server.upsert({
        where: {
          instanceId_pterodactylUuid: {
            instanceId: instance.id,
            pterodactylUuid: remote.uuid,
          },
        },
        update: {
          name: remote.name,
          identifier: remote.identifier,
          nodeId: remote.node,
          pterodactylId: remote.id,
          lastSyncedAt: new Date(),
        },
        create: {
          tenantId,
          instanceId: instance.id,
          pterodactylId: remote.id,
          pterodactylUuid: remote.uuid,
          identifier: remote.identifier,
          name: remote.name,
          nodeId: remote.node,
        },
      });
    }

    this.logger.log(
      `Synced ${remoteServers.length} server(s) from instance ${instance.id} (tenant ${tenantId})`,
    );
    return { synced: remoteServers.length };
  }

  findAllForTenant(tenantId: string, filters: ServerFilters): Promise<Server[]> {
    return this.prisma.server.findMany({
      where: {
        tenantId,
        ...(filters.instanceId ? { instanceId: filters.instanceId } : {}),
        ...(filters.q
          ? { name: { contains: filters.q, mode: 'insensitive' as const } }
          : {}),
      },
      orderBy: { name: 'asc' },
    });
  }

  async findOneForTenant(tenantId: string, id: string): Promise<Server> {
    const server = await this.prisma.server.findFirst({ where: { id, tenantId } });
    if (!server) {
      throw new NotFoundException('Server not found');
    }
    return server;
  }

  async getResources(tenantId: string, serverId: string): Promise<PterodactylResourceUsageDto> {
    const server = await this.findOneForTenant(tenantId, serverId);
    const instance = await this.instancesService.findOneForTenant(tenantId, server.instanceId);
    const apiKey = await this.getCredential(instance.id, CredentialKind.CLIENT_API_KEY);

    try {
      return await this.clientApi.getResourceUsage(instance.baseUrl, apiKey, server.identifier);
    } catch (error) {
      const message = error instanceof PterodactylError ? error.message : String(error);
      throw new BadGatewayException(`Could not fetch server resources: ${message}`);
    }
  }

  async sendPowerAction(
    tenantId: string,
    actorId: string,
    serverId: string,
    signal: PterodactylPowerSignal,
  ): Promise<void> {
    const server = await this.findOneForTenant(tenantId, serverId);
    const instance = await this.instancesService.findOneForTenant(tenantId, server.instanceId);
    const apiKey = await this.getCredential(instance.id, CredentialKind.CLIENT_API_KEY);

    try {
      await this.clientApi.sendPowerAction(instance.baseUrl, apiKey, server.identifier, signal);
    } catch (error) {
      const message = error instanceof PterodactylError ? error.message : String(error);
      await this.auditService.record({
        tenantId,
        actorId,
        action: `power.${signal}`,
        targetType: 'server',
        targetId: server.id,
        result: 'error',
        metadata: { message },
      });
      throw new BadGatewayException(`Could not send power action: ${message}`);
    }

    await this.auditService.record({
      tenantId,
      actorId,
      action: `power.${signal}`,
      targetType: 'server',
      targetId: server.id,
      result: 'success',
    });
  }

  private async getCredential(instanceId: string, kind: CredentialKind): Promise<string> {
    const credential = await this.prisma.instanceCredential.findUnique({
      where: { instanceId_kind: { instanceId, kind } },
    });
    if (!credential) {
      throw new BadRequestException(
        `Instance has no ${kind} credential configured`,
      );
    }
    return this.secrets.decrypt(Buffer.from(credential.ciphertext));
  }
}
