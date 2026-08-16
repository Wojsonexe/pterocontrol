import { Controller, Get, Query } from '@nestjs/common';
import { Event } from '@prisma/client';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { AuthenticatedUser } from '../auth/guards/jwt-auth.guard';
import { EventsService } from './events.service';

@Controller('events')
export class EventsController {
  constructor(private readonly eventsService: EventsService) {}

  @Get()
  findAll(
    @CurrentUser() user: AuthenticatedUser,
    @Query('instanceId') instanceId?: string,
    @Query('serverId') serverId?: string,
    @Query('type') type?: string,
  ): Promise<Event[]> {
    return this.eventsService.findAllForTenant(user.tenantId, { instanceId, serverId, type });
  }
}
