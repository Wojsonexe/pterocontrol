import { Controller, Get, Param, Post, Query } from '@nestjs/common';
import { Server } from '@prisma/client';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { Roles } from '../auth/decorators/roles.decorator';
import { AuthenticatedUser } from '../auth/guards/jwt-auth.guard';
import { ServersService, SyncResult } from './servers.service';

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

  @Roles('owner', 'admin')
  @Post('sync/:instanceId')
  sync(
    @CurrentUser() user: AuthenticatedUser,
    @Param('instanceId') instanceId: string,
  ): Promise<SyncResult> {
    return this.serversService.syncInstance(user.tenantId, instanceId);
  }
}
