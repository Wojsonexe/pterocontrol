import { Module } from '@nestjs/common';
import { AuditModule } from '../audit/audit.module';
import { InstancesModule } from '../instances/instances.module';
import { PterodactylModule } from '../pterodactyl/pterodactyl.module';
import { SecretsModule } from '../secrets/secrets.module';
import { ServersModule } from '../servers/servers.module';
import { ServerConfigController } from './server-config.controller';
import { ServerConfigService } from './server-config.service';

@Module({
  imports: [InstancesModule, ServersModule, PterodactylModule, SecretsModule, AuditModule],
  controllers: [ServerConfigController],
  providers: [ServerConfigService],
})
export class ServerConfigModule {}
