import { BadGatewayException, Injectable } from '@nestjs/common';
import {
  PterodactylAllocationDto,
  PterodactylClientApiClient,
  PterodactylError,
} from '@pterocontrol/pterodactyl-sdk';
import { AuditService } from '../audit/audit.service';
import { ServerCredentialResolverService } from '../servers/server-credential-resolver.service';

/** Same synchronous-proxy profile as Backups/Schedules - see those modules. */
@Injectable()
export class AllocationsService {
  constructor(
    private readonly credentials: ServerCredentialResolverService,
    private readonly clientApi: PterodactylClientApiClient,
    private readonly auditService: AuditService,
  ) {}

  async list(tenantId: string, serverId: string): Promise<PterodactylAllocationDto[]> {
    const { baseUrl, apiKey, identifier } = await this.credentials.resolveClientApiCredential(
      tenantId,
      serverId,
    );
    try {
      return await this.clientApi.listAllocations(baseUrl, apiKey, identifier);
    } catch (error) {
      throw this.toBadGateway(error, 'Could not list allocations');
    }
  }

  async create(
    tenantId: string,
    actorId: string,
    serverId: string,
  ): Promise<PterodactylAllocationDto> {
    const { baseUrl, apiKey, identifier } = await this.credentials.resolveClientApiCredential(
      tenantId,
      serverId,
    );
    try {
      const allocation = await this.clientApi.createAllocation(baseUrl, apiKey, identifier);
      await this.auditService.record({
        tenantId,
        actorId,
        action: 'allocation.create',
        targetType: 'server',
        targetId: serverId,
        result: 'success',
        metadata: { allocationId: allocation.id, port: allocation.port },
      });
      return allocation;
    } catch (error) {
      await this.recordFailure(tenantId, actorId, 'allocation.create', serverId, error);
      throw this.toBadGateway(error, 'Could not create allocation');
    }
  }

  async setNotes(
    tenantId: string,
    actorId: string,
    serverId: string,
    allocationId: number,
    notes: string,
  ): Promise<PterodactylAllocationDto> {
    const { baseUrl, apiKey, identifier } = await this.credentials.resolveClientApiCredential(
      tenantId,
      serverId,
    );
    try {
      const allocation = await this.clientApi.setAllocationNotes(
        baseUrl,
        apiKey,
        identifier,
        allocationId,
        notes,
      );
      await this.auditService.record({
        tenantId,
        actorId,
        action: 'allocation.set_notes',
        targetType: 'server',
        targetId: serverId,
        result: 'success',
        metadata: { allocationId },
      });
      return allocation;
    } catch (error) {
      await this.recordFailure(
        tenantId,
        actorId,
        'allocation.set_notes',
        serverId,
        error,
        allocationId,
      );
      throw this.toBadGateway(error, 'Could not update allocation notes');
    }
  }

  async setPrimary(
    tenantId: string,
    actorId: string,
    serverId: string,
    allocationId: number,
  ): Promise<void> {
    const { baseUrl, apiKey, identifier } = await this.credentials.resolveClientApiCredential(
      tenantId,
      serverId,
    );
    try {
      await this.clientApi.setPrimaryAllocation(baseUrl, apiKey, identifier, allocationId);
      await this.auditService.record({
        tenantId,
        actorId,
        action: 'allocation.set_primary',
        targetType: 'server',
        targetId: serverId,
        result: 'success',
        metadata: { allocationId },
      });
    } catch (error) {
      await this.recordFailure(
        tenantId,
        actorId,
        'allocation.set_primary',
        serverId,
        error,
        allocationId,
      );
      throw this.toBadGateway(error, 'Could not set primary allocation');
    }
  }

  async remove(
    tenantId: string,
    actorId: string,
    serverId: string,
    allocationId: number,
  ): Promise<void> {
    const { baseUrl, apiKey, identifier } = await this.credentials.resolveClientApiCredential(
      tenantId,
      serverId,
    );
    try {
      await this.clientApi.deleteAllocation(baseUrl, apiKey, identifier, allocationId);
      await this.auditService.record({
        tenantId,
        actorId,
        action: 'allocation.delete',
        targetType: 'server',
        targetId: serverId,
        result: 'success',
        metadata: { allocationId },
      });
    } catch (error) {
      await this.recordFailure(
        tenantId,
        actorId,
        'allocation.delete',
        serverId,
        error,
        allocationId,
      );
      throw this.toBadGateway(error, 'Could not delete allocation');
    }
  }

  private async recordFailure(
    tenantId: string,
    actorId: string,
    action: string,
    serverId: string,
    error: unknown,
    allocationId?: number,
  ): Promise<void> {
    const message = error instanceof PterodactylError ? error.message : String(error);
    await this.auditService.record({
      tenantId,
      actorId,
      action,
      targetType: 'server',
      targetId: serverId,
      result: 'error',
      metadata: { message, ...(allocationId !== undefined ? { allocationId } : {}) },
    });
  }

  private toBadGateway(error: unknown, prefix: string): BadGatewayException {
    const message = error instanceof PterodactylError ? error.message : String(error);
    return new BadGatewayException(`${prefix}: ${message}`);
  }
}
