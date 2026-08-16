import {
  BadGatewayException,
  BadRequestException,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import {
  PterodactylApplicationApiClient,
  PterodactylClientApiClient,
  PterodactylError,
  PterodactylPowerSignal,
  PterodactylResourceUsageDto,
} from '@pterocontrol/pterodactyl-sdk';
import { CredentialKind, ResourceSnapshot, Server } from '@prisma/client';
import { AuditService } from '../audit/audit.service';
import { EventsService } from '../events/events.service';
import { InstancesService } from '../instances/instances.service';
import { PrismaService } from '../prisma/prisma.service';
import { SecretsService } from '../secrets/secrets.service';

export interface ServerFilters {
  instanceId?: string;
  q?: string;
}

// BigInt fields can't be JSON.stringify'd by Express's default serializer
// (this crashed as a real 500 in live verification, not a hypothetical) -
// every BigInt column is stringified before leaving the service.
export interface ResourceSnapshotDto {
  id: string;
  serverId: string;
  observedAt: Date;
  cpuAbsolutePercent: number | null;
  memoryBytes: string | null;
  diskBytes: string | null;
  networkRxBytes: string | null;
  networkTxBytes: string | null;
  uptimeMs: string | null;
}

function toSnapshotDto(snapshot: ResourceSnapshot): ResourceSnapshotDto {
  return {
    id: snapshot.id,
    serverId: snapshot.serverId,
    observedAt: snapshot.observedAt,
    cpuAbsolutePercent: snapshot.cpuAbsolutePercent,
    memoryBytes: snapshot.memoryBytes?.toString() ?? null,
    diskBytes: snapshot.diskBytes?.toString() ?? null,
    networkRxBytes: snapshot.networkRxBytes?.toString() ?? null,
    networkTxBytes: snapshot.networkTxBytes?.toString() ?? null,
    uptimeMs: snapshot.uptimeMs?.toString() ?? null,
  };
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
    private readonly eventsService: EventsService,
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

    const existingUuids = new Set(
      (
        await this.prisma.server.findMany({
          where: { instanceId: instance.id },
          select: { pterodactylUuid: true },
        })
      ).map((s) => s.pterodactylUuid),
    );

    for (const remote of remoteServers) {
      // Mapping local -> global: (instanceId, pterodactylUuid) is the
      // natural key, never the bare Pterodactyl numeric id (not unique
      // across independent installs) - matches docs/architecture §2.
      const saved = await this.prisma.server.upsert({
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

      if (!existingUuids.has(remote.uuid)) {
        await this.eventsService.record({
          tenantId,
          instanceId: instance.id,
          serverId: saved.id,
          type: 'server_created',
          payload: { name: remote.name, identifier: remote.identifier },
          dedupKey: `server_created:${instance.id}:${remote.uuid}`,
        });
      }
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

    let usage: PterodactylResourceUsageDto;
    try {
      usage = await this.clientApi.getResourceUsage(instance.baseUrl, apiKey, server.identifier);
    } catch (error) {
      const message = error instanceof PterodactylError ? error.message : String(error);
      throw new BadGatewayException(`Could not fetch server resources: ${message}`);
    }

    // Every live look is also a data point - this is the only source of
    // history until the federation-worker's periodic collector exists
    // (see IMPLEMENTATION_STATUS.md). A failed clientApi call above never
    // reaches here, so no snapshot is recorded for a failed read.
    await this.prisma.resourceSnapshot.create({
      data: {
        tenantId,
        serverId: server.id,
        cpuAbsolutePercent: usage.cpuAbsolutePercent,
        memoryBytes: BigInt(Math.round(usage.memoryBytes)),
        diskBytes: BigInt(Math.round(usage.diskBytes)),
        networkRxBytes: BigInt(Math.round(usage.networkRxBytes)),
        networkTxBytes: BigInt(Math.round(usage.networkTxBytes)),
        uptimeMs: BigInt(Math.round(usage.uptimeMs)),
      },
    });

    return usage;
  }

  async getResourceHistory(
    tenantId: string,
    serverId: string,
    limit = 100,
  ): Promise<ResourceSnapshotDto[]> {
    await this.findOneForTenant(tenantId, serverId); // tenant-ownership check
    const snapshots = await this.prisma.resourceSnapshot.findMany({
      where: { tenantId, serverId },
      orderBy: { observedAt: 'desc' },
      take: Math.min(limit, 500),
    });
    return snapshots.map(toSnapshotDto);
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
