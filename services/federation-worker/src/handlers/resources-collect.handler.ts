import { Injectable } from '@nestjs/common';
import { CredentialKind } from '@prisma/client';
import { PterodactylClientApiClient } from '@pterocontrol/pterodactyl-sdk';
import { MessageEnvelope } from '@pterocontrol/rabbitmq';
import { SecretsService } from '@pterocontrol/secrets';
import { PermanentJobError } from '../errors/permanent-job-error';
import { PrismaService } from '../prisma/prisma.service';

/**
 * The background collector referenced throughout IMPLEMENTATION_STATUS.md
 * since FAZA 8 - fetches one server's live resource usage and writes a
 * ResourceSnapshot row, same shape as ServersService.getResources()'s
 * inline write (see that method's own doc comment), just triggered by
 * ResourceCollectionScheduler's per-minute sweep instead of a live GET.
 */
@Injectable()
export class ResourcesCollectHandler {
  constructor(
    private readonly prisma: PrismaService,
    private readonly clientApi: PterodactylClientApiClient,
    private readonly secrets: SecretsService,
  ) {}

  async handle(envelope: MessageEnvelope): Promise<void> {
    const serverId = envelope.serverId;
    if (!serverId) {
      throw new PermanentJobError(
        'federation.resources.collect envelope is missing serverId',
      );
    }

    const server = await this.prisma.server.findFirst({
      where: { id: serverId, tenantId: envelope.tenantId },
    });
    if (!server) {
      throw new PermanentJobError(
        `Server ${serverId} not found for tenant ${envelope.tenantId}`,
      );
    }

    const instance = await this.prisma.pterodactylInstance.findUnique({
      where: { id: server.instanceId },
    });
    if (!instance) {
      throw new PermanentJobError(
        `Instance ${server.instanceId} not found for server ${serverId}`,
      );
    }

    const credential = await this.prisma.instanceCredential.findUnique({
      where: {
        instanceId_kind: {
          instanceId: instance.id,
          kind: CredentialKind.CLIENT_API_KEY,
        },
      },
    });
    if (!credential) {
      // Not every instance necessarily has a Client API key configured -
      // a real, expected state (see InstanceCredential), not a bug. Still
      // permanent: retrying without credentials will never help, and the
      // scheduler will simply queue this server again next minute anyway.
      throw new PermanentJobError(
        `Instance ${instance.id} has no Client API credential configured`,
      );
    }
    const apiKey = this.secrets.decrypt(Buffer.from(credential.ciphertext));

    const usage = await this.clientApi.getResourceUsage(
      instance.baseUrl,
      apiKey,
      server.identifier,
    );

    await this.prisma.resourceSnapshot.create({
      data: {
        tenantId: envelope.tenantId,
        serverId: server.id,
        cpuAbsolutePercent: usage.cpuAbsolutePercent,
        memoryBytes: BigInt(Math.round(usage.memoryBytes)),
        diskBytes: BigInt(Math.round(usage.diskBytes)),
        networkRxBytes: BigInt(Math.round(usage.networkRxBytes)),
        networkTxBytes: BigInt(Math.round(usage.networkTxBytes)),
        uptimeMs: BigInt(Math.round(usage.uptimeMs)),
      },
    });
  }
}
