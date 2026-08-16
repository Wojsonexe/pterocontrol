import { Module } from '@nestjs/common';
import { InstancesModule } from '../instances/instances.module';
import { PterodactylModule } from '../pterodactyl/pterodactyl.module';
import { SecretsModule } from '../secrets/secrets.module';
import { ServersController } from './servers.controller';
import { ServersService } from './servers.service';

@Module({
  imports: [InstancesModule, PterodactylModule, SecretsModule],
  controllers: [ServersController],
  providers: [ServersService],
  exports: [ServersService],
})
export class ServersModule {}
