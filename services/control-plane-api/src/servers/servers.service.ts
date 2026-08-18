import {
  BadGatewayException,
  BadRequestException,
  Injectable,
  Logger,
  NotFoundException,
  ServiceUnavailableException,
} from '@nestjs/common';
import {
  PterodactylClientApiClient,
  PterodactylError,
  PterodactylPowerSignal,
  PterodactylResourceUsageDto,
} from '@pterocontrol/pterodactyl-sdk';
import {
  createEnvelope,
  EXCHANGES,
  RabbitMqPublisherService,
  ROUTING_KEYS,
} from '@pterocontrol/rabbitmq';
import { SecretsService } from '@pterocontrol/secrets';
import { CredentialKind, ResourceSnapshot, Server } from '@prisma/client';
import { AuditService } from '../audit/audit.service';
import { InstancesService } from '../instances/instances.service';
import { PrismaService } from '../prisma/prisma.service';

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

export interface QueuedJob {
  status: 'queued';
  jobId: string;
}

/**
 * Global server model: aggregates Server rows across every
 * PterodactylInstance a tenant owns. Inventory sync (syncInstance()) and
 * periodic resource collection are both async now (FAZA 9b) - this
 * service only publishes the job and returns; federation-worker does the
 * actual Application API listServers() call, the upsert, and the
 * server_created Event emission. This service still owns live
 * synchronous reads (getResources(), power actions) - a different
 * credential (Client API key) than the Application API key used for
 * inventory sync.
 */
@Injectable()
export class ServersService {
  private readonly logger = new Logger(ServersService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly instancesService: InstancesService,
    private readonly secrets: SecretsService,
    private readonly clientApi: PterodactylClientApiClient,
    private readonly auditService: AuditService,
    private readonly publisher: RabbitMqPublisherService,
  ) {}

  // Server inventory sync (list every server on the instance, upsert the
  // global Server rows) is the "heavier" of the two federation calls -
  // one HTTP request to Pterodactyl per instance, N upserts locally. This
  // publishes federation.server.sync and returns immediately;
  // federation-worker does the actual listServers()+upsert (see
  // services/federation-worker/src/handlers/server-sync.handler.ts) -
  // same upsert-by-(instanceId,pterodactylUuid) and server_created event
  // logic that used to live here.
  async syncInstance(tenantId: string, instanceId: string): Promise<QueuedJob> {
    const instance = await this.instancesService.findOneForTenant(tenantId, instanceId);

    const envelope = createEnvelope({
      tenantId,
      instanceId: instance.id,
      payload: {},
    });
    try {
      this.publisher.publish(
        EXCHANGES.FEDERATION_COMMANDS,
        ROUTING_KEYS.SERVER_SYNC,
        envelope,
      );
    } catch (error) {
      throw new ServiceUnavailableException(
        `Could not queue server sync: ${String(error)}`,
      );
    }

    return { status: 'queued', jobId: envelope.jobId };
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

    // Every live look is also a data point, in addition to the periodic
    // background collection now done by federation-worker's
    // resources-collect handler (see ResourceCollectionScheduler). A
    // failed clientApi call above never reaches here, so no snapshot is
    // recorded for a failed read.
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
