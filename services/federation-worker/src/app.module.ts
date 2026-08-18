import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { validateEnv } from './config/env.validation';
import { ConsumerModule } from './consumer/consumer.module';
import { PrismaModule } from './prisma/prisma.module';
import { RabbitmqModule } from './rabbitmq/rabbitmq.module';

// PterodactylModule and SecretsModule are not imported here directly -
// same convention as control-plane-api's AppModule: only the leaf module
// that actually needs them imports them (HandlersModule, in this case).
// PrismaModule/RabbitmqModule are both @Global() so importing them once
// here is enough for the whole graph.
@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true, validate: validateEnv }),
    PrismaModule,
    RabbitmqModule,
    ConsumerModule,
  ],
})
export class AppModule {}
