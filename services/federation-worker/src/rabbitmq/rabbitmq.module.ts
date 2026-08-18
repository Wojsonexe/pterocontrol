import { Global, Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import {
  RabbitMqConnectionService,
  RabbitMqPublisherService,
} from '@pterocontrol/rabbitmq';

/**
 * Same connect()-fired-but-not-awaited pattern as control-plane-api's
 * RabbitmqModule (see that module's doc comment) - if RabbitMQ is down
 * at boot, this process still starts; FederationConsumerService polls
 * isConnected() and starts consuming once the connection comes up.
 */
@Global()
@Module({
  providers: [
    {
      provide: RabbitMqConnectionService,
      useFactory: (config: ConfigService): RabbitMqConnectionService => {
        const url = config.getOrThrow<string>('RABBITMQ_URL');
        const service = new RabbitMqConnectionService(url);
        void service.connect();
        return service;
      },
      inject: [ConfigService],
    },
    RabbitMqPublisherService,
  ],
  exports: [RabbitMqConnectionService, RabbitMqPublisherService],
})
export class RabbitmqModule {}
