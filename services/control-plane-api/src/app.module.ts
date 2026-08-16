import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { AuthModule } from './auth/auth.module';
import { validateEnv } from './config/env.validation';
import { HealthModule } from './health/health.module';
import { InstancesModule } from './instances/instances.module';
import { PrismaModule } from './prisma/prisma.module';
import { SecretsModule } from './secrets/secrets.module';
import { ServersModule } from './servers/servers.module';
import { TenantsModule } from './tenants/tenants.module';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true, validate: validateEnv }),
    HealthModule,
    SecretsModule,
    PrismaModule,
    AuthModule,
    TenantsModule,
    InstancesModule,
    ServersModule,
  ],
})
export class AppModule {}
