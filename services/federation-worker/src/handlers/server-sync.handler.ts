import { Injectable, Logger } from '@nestjs/common';
import { CredentialKind } from '@prisma/client';
import { PterodactylApplicationApiClient } from '@pterocontrol/pterodactyl-sdk';
import { MessageEnvelope } from '@pterocontrol/rabbitmq';
import { SecretsService } from '@pterocontrol/secrets';
import { PermanentJobError } from '../errors/permanent-job-error';
import { recordEvent } from '../events/record-event';
import { PrismaService } from '../prisma/prisma.service';

/**
 * The background equivalent of what ServersService.syncInstance() used
 * to do inline - lists every server on the instance and upserts the
 * global Server rows, keyed by (instanceId, pterodactylUuid), never the
 * bare Pterodactyl numeric id (not unique across independent installs -
 * see schema.prisma's own doc comment on Server). Emits server_created
 * only for UUIDs not already known before this run.
 */
@Injectable()
export class ServerSyncHandler {
  private readonly logger = new Logger(ServerSyncHandler.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly applicationApi: PterodactylApplicationApiClient,
    private readonly secrets: SecretsService,
  ) {}

  async handle(envelope: MessageEnvelope): Promise<void> {
    const instanceId = envelope.instanceId;
    if (!instanceId) {
      throw new PermanentJobError(
        'federation.server.sync envelope is missing instanceId',
      );
    }

    const instance = await this.prisma.pterodactylInstance.findFirst({
      where: { id: instanceId, tenantId: envelope.tenantId },
    });
    if (!instance) {
      throw new PermanentJobError(
        `Instance ${instanceId} not found for tenant ${envelope.tenantId}`,
      );
    }

    const credential = await this.prisma.instanceCredential.findUnique({
      where: {
        instanceId_kind: {
          instanceId,
          kind: CredentialKind.APPLICATION_API_KEY,
        },
      },
    });
    if (!credential) {
      throw new PermanentJobError(
        `Instance ${instanceId} has no Application API credential stored`,
      );
    }
    const apiKey = this.secrets.decrypt(Buffer.from(credential.ciphertext));

    // Not caught here - a Pterodactyl-side failure propagates to
    // FederationConsumerService for retry/DLQ classification (unlike
    // control-plane-api's old synchronous version, there is no HTTP
    // caller waiting for a clean 502 anymore).
    const remoteServers = await this.applicationApi.listServers(
      instance.baseUrl,
      apiKey,
    );

    const existingUuids = new Set(
      (
        await this.prisma.server.findMany({
          where: { instanceId },
          select: { pterodactylUuid: true },
        })
      ).map((s) => s.pterodactylUuid),
    );

    for (const remote of remoteServers) {
      const saved = await this.prisma.server.upsert({
        where: {
          instanceId_pterodactylUuid: {
            instanceId,
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
          tenantId: envelope.tenantId,
          instanceId,
          pterodactylId: remote.id,
          pterodactylUuid: remote.uuid,
          identifier: remote.identifier,
          name: remote.name,
          nodeId: remote.node,
        },
      });

      if (!existingUuids.has(remote.uuid)) {
        await recordEvent(this.prisma, {
          tenantId: envelope.tenantId,
          instanceId,
          serverId: saved.id,
          type: 'server_created',
          payload: { name: remote.name, identifier: remote.identifier },
          dedupKey: `server_created:${instanceId}:${remote.uuid}`,
        });
      }
    }

    this.logger.log(
      `Synced ${remoteServers.length} server(s) from instance ${instanceId} (tenant ${envelope.tenantId})`,
    );
  }
}
