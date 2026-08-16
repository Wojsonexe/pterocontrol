import { BadGatewayException, BadRequestException, Injectable } from '@nestjs/common';
import {
  PterodactylClientApiClient,
  PterodactylError,
  PterodactylStartupVariableDto,
} from '@pterocontrol/pterodactyl-sdk';
import { SecretsService } from '@pterocontrol/secrets';
import { CredentialKind } from '@prisma/client';
import { AuditService } from '../audit/audit.service';
import { InstancesService } from '../instances/instances.service';
import { PrismaService } from '../prisma/prisma.service';
import { ServersService } from '../servers/servers.service';
import { UpdateStartupVariableDto } from './dto/update-startup-variable.dto';

/**
 * Same synchronous-proxy profile as BackupsService/ServersService's power
 * actions - one quick outbound call, no RabbitMQ. See that module's own
 * doc comment and IMPLEMENTATION_STATUS.md for the API-contract-
 * provenance caveat that applies here too (not verified against the
 * Flutter app, which has no REST integration for Startup/Environment
 * either - its tab is a ComingSoonView placeholder).
 */
@Injectable()
export class ServerConfigService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly instancesService: InstancesService,
    private readonly serversService: ServersService,
    private readonly secrets: SecretsService,
    private readonly clientApi: PterodactylClientApiClient,
    private readonly auditService: AuditService,
  ) {}

  async getStartupVariables(
    tenantId: string,
    serverId: string,
  ): Promise<PterodactylStartupVariableDto[]> {
    const { baseUrl, apiKey, identifier } = await this.resolveServer(tenantId, serverId);
    try {
      return await this.clientApi.getStartupVariables(baseUrl, apiKey, identifier);
    } catch (error) {
      throw this.toBadGateway(error, 'Could not fetch startup variables');
    }
  }

  async updateStartupVariable(
    tenantId: string,
    actorId: string,
    serverId: string,
    dto: UpdateStartupVariableDto,
  ): Promise<PterodactylStartupVariableDto> {
    const { baseUrl, apiKey, identifier } = await this.resolveServer(tenantId, serverId);

    // Checked client-side first, not just left to Pterodactyl's own
    // rejection - a 400 "not editable" here is far clearer than an
    // opaque 502 surfaced from whatever Pterodactyl happens to return
    // for a locked variable.
    let variables: PterodactylStartupVariableDto[];
    try {
      variables = await this.clientApi.getStartupVariables(baseUrl, apiKey, identifier);
    } catch (error) {
      throw this.toBadGateway(error, 'Could not fetch startup variables');
    }
    const variable = variables.find((v) => v.envVariable === dto.key);
    if (!variable) {
      throw new BadRequestException(`Unknown startup variable "${dto.key}"`);
    }
    if (!variable.isEditable) {
      throw new BadRequestException(`Startup variable "${dto.key}" is not editable`);
    }

    try {
      const updated = await this.clientApi.updateStartupVariable(
        baseUrl,
        apiKey,
        identifier,
        dto.key,
        dto.value,
      );
      await this.auditService.record({
        tenantId,
        actorId,
        action: 'server_config.update_startup_variable',
        targetType: 'server',
        targetId: serverId,
        result: 'success',
        metadata: { key: dto.key, value: dto.value },
      });
      return updated;
    } catch (error) {
      const message = error instanceof PterodactylError ? error.message : String(error);
      await this.auditService.record({
        tenantId,
        actorId,
        action: 'server_config.update_startup_variable',
        targetType: 'server',
        targetId: serverId,
        result: 'error',
        metadata: { key: dto.key, message },
      });
      throw this.toBadGateway(error, 'Could not update startup variable');
    }
  }

  private async resolveServer(
    tenantId: string,
    serverId: string,
  ): Promise<{ baseUrl: string; apiKey: string; identifier: string }> {
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

  private toBadGateway(error: unknown, prefix: string): BadGatewayException {
    const message = error instanceof PterodactylError ? error.message : String(error);
    return new BadGatewayException(`${prefix}: ${message}`);
  }
}
