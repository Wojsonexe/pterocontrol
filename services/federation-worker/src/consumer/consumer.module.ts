import { Module } from '@nestjs/common';
import { HandlersModule } from '../handlers/handlers.module';
import { IdempotencyModule } from '../idempotency/idempotency.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { FederationConsumerService } from './federation-consumer.service';
import { NotificationConsumerService } from './notification-consumer.service';

@Module({
  imports: [HandlersModule, IdempotencyModule, NotificationsModule],
  providers: [FederationConsumerService, NotificationConsumerService],
})
export class ConsumerModule {}
