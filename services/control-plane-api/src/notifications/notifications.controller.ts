import { Controller, Get, Query } from '@nestjs/common';
import { Notification, NotificationStatus } from '@prisma/client';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { AuthenticatedUser } from '../auth/guards/jwt-auth.guard';
import { NotificationsService } from './notifications.service';

@Controller('notifications')
export class NotificationsController {
  constructor(private readonly notificationsService: NotificationsService) {}

  @Get()
  findAll(
    @CurrentUser() user: AuthenticatedUser,
    @Query('channelId') channelId?: string,
    @Query('alertId') alertId?: string,
    @Query('status') status?: NotificationStatus,
  ): Promise<Notification[]> {
    return this.notificationsService.findAllNotificationsForTenant(user.tenantId, {
      channelId,
      alertId,
      status,
    });
  }
}
