import { BadRequestException, Injectable } from '@nestjs/common';
import { CredentialKind } from '@prisma/client';
import { SecretsService } from '@pterocontrol/secrets';
import { InstancesService } from '../instances/instances.service';
import { PrismaService } from '../prisma/prisma.service';
import { ServersService } from './servers.service';

export interface ResolvedServerCredential {
  baseUrl: string;
  apiKey: string;
  identifier: string;
}

/**
 * The "tenant-scoped server lookup -> instance lookup -> decrypt Client
 * API credential" sequence every synchronous Pterodactyl proxy module
 * needs (Backups, Server Configuration, and now Schedules/Allocations/
 * Databases/Activity). Extracted here once this pattern started
 * repeating across five+ modules - each new copy was the exact same
 * ~15 lines, and a bug in credential resolution is exactly the kind of
 * thing that should be fixed in one place, not five.
 */
@Injectable()
export class ServerCredentialResolverService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly instancesService: InstancesService,
    private readonly serversService: ServersService,
    private readonly secrets: SecretsService,
  ) {}

  async resolveClientApiCredential(
    tenantId: string,
    serverId: string,
  ): Promise<ResolvedServerCredential> {
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
}
