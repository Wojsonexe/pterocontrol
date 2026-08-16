import { Module } from '@nestjs/common';
import { PterodactylModule } from '../pterodactyl/pterodactyl.module';
import { NotificationChannelsController } from './notification-channels.controller';
import { NotificationsController } from './notifications.controller';
import { NotificationsService } from './notifications.service';

@Module({
  imports: [PterodactylModule],
  controllers: [NotificationChannelsController, NotificationsController],
  providers: [NotificationsService],
  exports: [NotificationsService],
})
export class NotificationsModule {}
