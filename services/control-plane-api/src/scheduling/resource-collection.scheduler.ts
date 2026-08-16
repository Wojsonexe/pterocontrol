import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import {
  createEnvelope,
  EXCHANGES,
  RabbitMqPublisherService,
  ROUTING_KEYS,
} from '@pterocontrol/rabbitmq';
import { PrismaService } from '../prisma/prisma.service';

/**
 * The background half of ResourceSnapshot collection (FAZA 9b) - every
 * live GET /servers/:id/resources still also writes a snapshot (see
 * ServersService.getResources), but this is what fills the history for
 * servers nobody happens to be looking at right now. Publishes one
 * federation.resources.collect job per server, every minute; the actual
 * Client API call + ResourceSnapshot write happens in federation-worker
 * (see resources-collect.handler.ts), never here - this only reads the
 * server list and publishes.
 *
 * Deliberately no per-instance rate limiting yet: at MVP scale (a
 * handful of tenants/instances) one poll/minute/server is well within
 * normal Pterodactyl panel usage. A tenant/instance with many servers
 * would need this staggered or rate-limited - documented as a known
 * scaling limitation in IMPLEMENTATION_STATUS.md, not solved here.
 */
@Injectable()
export class ResourceCollectionScheduler {
  private readonly logger = new Logger(ResourceCollectionScheduler.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly publisher: RabbitMqPublisherService,
  ) {}

  @Cron(CronExpression.EVERY_MINUTE)
  async collectAll(): Promise<void> {
    const servers = await this.prisma.server.findMany({
      select: { id: true, tenantId: true, instanceId: true },
    });

    if (servers.length === 0) {
      return;
    }

    let published = 0;
    for (const server of servers) {
      const envelope = createEnvelope({
        tenantId: server.tenantId,
        instanceId: server.instanceId,
        serverId: server.id,
        payload: {},
      });
      try {
        this.publisher.publish(
          EXCHANGES.FEDERATION_COMMANDS,
          ROUTING_KEYS.RESOURCES_COLLECT,
          envelope,
        );
        published++;
      } catch (error) {
        // RabbitMQ down: skip this tick entirely rather than throwing -
        // a scheduled job has no HTTP caller to return a controlled
        // error to, and the next tick will simply try again once the
        // broker recovers (RabbitMqConnectionService auto-reconnects).
        this.logger.warn(
          `Could not queue resource collection (RabbitMQ unavailable): ${String(error)}`,
        );
        break;
      }
    }

    if (published > 0) {
      this.logger.debug(`Queued resource collection for ${published} server(s)`);
    }
  }
}
