import {
  Body,
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  Post,
  Query,
} from '@nestjs/common';
import { Server } from '@prisma/client';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { Roles } from '../auth/decorators/roles.decorator';
import { AuthenticatedUser } from '../auth/guards/jwt-auth.guard';
import { PterodactylResourceUsageDto } from '../pterodactyl/pterodactyl-client-api.client';
import { PowerActionDto } from './dto/power-action.dto';
import { ResourceSnapshotDto, ServersService, SyncResult } from './servers.service';

@Controller('servers')
export class ServersController {
  constructor(private readonly serversService: ServersService) {}

  @Get()
  findAll(
    @CurrentUser() user: AuthenticatedUser,
    @Query('instanceId') instanceId?: string,
    @Query('q') q?: string,
  ): Promise<Server[]> {
    return this.serversService.findAllForTenant(user.tenantId, { instanceId, q });
  }

  @Get(':id')
  findOne(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id') id: string,
  ): Promise<Server> {
    return this.serversService.findOneForTenant(user.tenantId, id);
  }

  @Get(':id/resources')
  getResources(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id') id: string,
  ): Promise<PterodactylResourceUsageDto> {
    return this.serversService.getResources(user.tenantId, id);
  }

  @Get(':id/resources/history')
  getResourceHistory(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id') id: string,
    @Query('limit') limit?: string,
  ): Promise<ResourceSnapshotDto[]> {
    return this.serversService.getResourceHistory(
      user.tenantId,
      id,
      limit ? Number.parseInt(limit, 10) : undefined,
    );
  }

  @Roles('owner', 'admin')
  @Post(':id/power')
  @HttpCode(HttpStatus.ACCEPTED)
  async sendPowerAction(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id') id: string,
    @Body() dto: PowerActionDto,
  ): Promise<{ accepted: true }> {
    await this.serversService.sendPowerAction(user.tenantId, user.sub, id, dto.action);
    return { accepted: true };
  }

  @Roles('owner', 'admin')
  @Post('sync/:instanceId')
  sync(
    @CurrentUser() user: AuthenticatedUser,
    @Param('instanceId') instanceId: string,
  ): Promise<SyncResult> {
    return this.serversService.syncInstance(user.tenantId, instanceId);
  }
}
