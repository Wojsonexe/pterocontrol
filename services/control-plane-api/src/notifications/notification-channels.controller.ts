import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  Post,
} from '@nestjs/common';
import { NotificationChannel } from '@prisma/client';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { Roles } from '../auth/decorators/roles.decorator';
import { AuthenticatedUser } from '../auth/guards/jwt-auth.guard';
import { CreateNotificationChannelDto } from './dto/create-notification-channel.dto';
import { NotificationsService } from './notifications.service';

@Controller('notification-channels')
export class NotificationChannelsController {
  constructor(private readonly notificationsService: NotificationsService) {}

  @Roles('owner', 'admin')
  @Post()
  create(
    @CurrentUser() user: AuthenticatedUser,
    @Body() dto: CreateNotificationChannelDto,
  ): Promise<NotificationChannel> {
    return this.notificationsService.createChannel(user.tenantId, dto);
  }

  @Get()
  findAll(@CurrentUser() user: AuthenticatedUser): Promise<NotificationChannel[]> {
    return this.notificationsService.findAllChannelsForTenant(user.tenantId);
  }

  @Roles('owner', 'admin')
  @Delete(':id')
  @HttpCode(HttpStatus.NO_CONTENT)
  async remove(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id') id: string,
  ): Promise<void> {
    await this.notificationsService.removeChannel(user.tenantId, id);
  }
}
