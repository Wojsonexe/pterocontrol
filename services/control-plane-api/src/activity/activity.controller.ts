import { Controller, Get, Param } from '@nestjs/common';
import { PterodactylActivityLogDto } from '@pterocontrol/pterodactyl-sdk';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { AuthenticatedUser } from '../auth/guards/jwt-auth.guard';
import { ActivityService } from './activity.service';

@Controller('servers/:serverId/activity')
export class ActivityController {
  constructor(private readonly activityService: ActivityService) {}

  @Get()
  list(
    @CurrentUser() user: AuthenticatedUser,
    @Param('serverId') serverId: string,
  ): Promise<PterodactylActivityLogDto[]> {
    return this.activityService.list(user.tenantId, serverId);
  }
}
