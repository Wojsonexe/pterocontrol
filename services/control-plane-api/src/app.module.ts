import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { ActivityModule } from './activity/activity.module';
import { AlertsModule } from './alerts/alerts.module';
import { AllocationsModule } from './allocations/allocations.module';
import { AuthModule } from './auth/auth.module';
import { BackupsModule } from './backups/backups.module';
import { validateEnv } from './config/env.validation';
import { EventsModule } from './events/events.module';
import { HealthModule } from './health/health.module';
import { InstancesModule } from './instances/instances.module';
import { PrismaModule } from './prisma/prisma.module';
import { RabbitmqModule } from './rabbitmq/rabbitmq.module';
import { SchedulesModule } from './schedules/schedules.module';
import { SchedulingModule } from './scheduling/scheduling.module';
import { SecretsModule } from './secrets/secrets.module';
import { ServerConfigModule } from './server-config/server-config.module';
import { ServerDatabasesModule } from './server-databases/server-databases.module';
import { ServersModule } from './servers/servers.module';
import { TenantsModule } from './tenants/tenants.module';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true, validate: validateEnv }),
    HealthModule,
    SecretsModule,
    PrismaModule,
    RabbitmqModule,
    SchedulingModule,
    AuthModule,
    TenantsModule,
    InstancesModule,
    ServersModule,
    EventsModule,
    AlertsModule,
    BackupsModule,
    ServerConfigModule,
    SchedulesModule,
    AllocationsModule,
    ServerDatabasesModule,
    ActivityModule,
  ],
})
export class AppModule {}
