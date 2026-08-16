import { BadGatewayException, Injectable } from '@nestjs/common';
import {
  PterodactylActivityLogDto,
  PterodactylClientApiClient,
  PterodactylError,
} from '@pterocontrol/pterodactyl-sdk';
import { ServerCredentialResolverService } from '../servers/server-credential-resolver.service';

/**
 * Read-only proxy to Pterodactyl's own per-server activity log - a
 * different thing from this Control Plane's own `Event`/`AuditLog`
 * tables (those are Postgres source-of-truth for CP-observed/CP-driven
 * actions; this is whatever Pterodactyl itself recorded). No mutations,
 * so no AuditLog writes here - nothing to audit about a read.
 */
@Injectable()
export class ActivityService {
  constructor(
    private readonly credentials: ServerCredentialResolverService,
    private readonly clientApi: PterodactylClientApiClient,
  ) {}

  async list(tenantId: string, serverId: string): Promise<PterodactylActivityLogDto[]> {
    const { baseUrl, apiKey, identifier } = await this.credentials.resolveClientApiCredential(
      tenantId,
      serverId,
    );
    try {
      return await this.clientApi.listActivity(baseUrl, apiKey, identifier);
    } catch (error) {
      const message = error instanceof PterodactylError ? error.message : String(error);
      throw new BadGatewayException(`Could not list activity: ${message}`);
    }
  }
}
