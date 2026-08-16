import { Module } from '@nestjs/common';
import { PterodactylModule } from '../pterodactyl/pterodactyl.module';
import { NotificationDispatchHandler } from './notification-dispatch.handler';
import { WebhookHttpClient } from './webhook-http.client';

@Module({
  imports: [PterodactylModule],
  providers: [WebhookHttpClient, NotificationDispatchHandler],
  exports: [NotificationDispatchHandler],
})
export class NotificationsModule {}
