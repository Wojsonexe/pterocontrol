import { Injectable, Logger } from '@nestjs/common';
import { CredentialKind, InstanceStatus } from '@prisma/client';
import {
  PterodactylApplicationApiClient,
  SsrfValidatorService,
} from '@pterocontrol/pterodactyl-sdk';
import { MessageEnvelope } from '@pterocontrol/rabbitmq';
import { SecretsService } from '@pterocontrol/secrets';
import { PermanentJobError } from '../errors/permanent-job-error';
import { recordEvent } from '../events/record-event';
import { PrismaService } from '../prisma/prisma.service';

/**
 * The background equivalent of what InstancesService.resync() used to do
 * inline (see control-plane-api's instances.service.ts) - re-tests
 * connectivity and updates status/lastSyncedAt/lastError, emitting
 * instance_status_changed only on a real transition. The status write
 * always happens, success or failure; the triggering error (if any) is
 * rethrown afterwards so FederationConsumerService's retry/DLQ
 * classification runs on the real Pterodactyl error, not a wrapped one -
 * a transient network blip gets retried (and the DB already reflects
 * UNREACHABLE in the meantime), a bad credential goes straight to DLQ
 * without wasting retries neither of which changes the outcome.
 */
@Injectable()
export class InstanceSyncHandler {
  private readonly logger = new Logger(InstanceSyncHandler.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly ssrfValidator: SsrfValidatorService,
    private readonly applicationApi: PterodactylApplicationApiClient,
    private readonly secrets: SecretsService,
  ) {}

  async handle(envelope: MessageEnvelope): Promise<void> {
    const instanceId = envelope.instanceId;
    if (!instanceId) {
      throw new PermanentJobError(
        'federation.instance.sync envelope is missing instanceId',
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

    const previousStatus = instance.status;
    let caughtError: Error | undefined;
    let newStatus: InstanceStatus;

    try {
      await this.ssrfValidator.assertSafeInstanceUrl(instance.baseUrl);
      await this.applicationApi.testConnection(instance.baseUrl, apiKey);
      await this.prisma.pterodactylInstance.update({
        where: { id: instanceId },
        data: {
          status: InstanceStatus.ONLINE,
          lastSyncedAt: new Date(),
          lastError: null,
        },
      });
      newStatus = InstanceStatus.ONLINE;
    } catch (error) {
      caughtError = error instanceof Error ? error : new Error(String(error));
      const message = caughtError.message;
      this.logger.warn(
        `Instance ${instanceId} (tenant ${envelope.tenantId}) connectivity test failed: ${message}`,
      );
      await this.prisma.pterodactylInstance.update({
        where: { id: instanceId },
        data: { status: InstanceStatus.UNREACHABLE, lastError: message },
      });
      newStatus = InstanceStatus.UNREACHABLE;
    }

    if (previousStatus !== newStatus) {
      await recordEvent(this.prisma, {
        tenantId: envelope.tenantId,
        instanceId,
        type: 'instance_status_changed',
        payload: { from: previousStatus, to: newStatus },
        dedupKey: `instance_status_changed:${instanceId}:${previousStatus}->${newStatus}:${envelope.jobId}`,
      });
    }

    if (caughtError !== undefined) {
      throw caughtError;
    }
  }
}
