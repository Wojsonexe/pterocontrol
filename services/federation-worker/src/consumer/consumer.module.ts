import { Module } from '@nestjs/common';
import { HandlersModule } from '../handlers/handlers.module';
import { IdempotencyModule } from '../idempotency/idempotency.module';
import { FederationConsumerService } from './federation-consumer.service';

@Module({
  imports: [HandlersModule, IdempotencyModule],
  providers: [FederationConsumerService],
})
export class ConsumerModule {}
