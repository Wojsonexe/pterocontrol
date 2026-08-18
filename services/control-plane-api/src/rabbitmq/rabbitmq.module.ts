import { Global, Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import {
  RabbitMqConnectionService,
  RabbitMqPublisherService,
} from '@pterocontrol/rabbitmq';

/**
 * connect() is fired here but never awaited by the factory - if RabbitMQ
 * is down at boot, the API must still start and serve everything that
 * doesn't need the broker (this is exactly the "RabbitMQ down -> API
 * does not crash" requirement). RabbitMqConnectionService retries the
 * connection on its own timer; getChannel()/publish() throw synchronously
 * until it succeeds, which is what lets callers return a controlled 503
 * instead of hanging (see instances.service.ts, servers.service.ts,
 * health.controller.ts).
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
