import { Module } from '@nestjs/common';
import { AuditModule } from '../audit/audit.module';
import { InstancesModule } from '../instances/instances.module';
import { PterodactylModule } from '../pterodactyl/pterodactyl.module';
import { SecretsModule } from '../secrets/secrets.module';
import { ServersModule } from '../servers/servers.module';
import { BackupsController } from './backups.controller';
import { BackupsService } from './backups.service';

@Module({
  imports: [InstancesModule, ServersModule, PterodactylModule, SecretsModule, AuditModule],
  controllers: [BackupsController],
  providers: [BackupsService],
})
export class BackupsModule {}
