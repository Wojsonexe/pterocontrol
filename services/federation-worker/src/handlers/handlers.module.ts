import { Module } from '@nestjs/common';
import { PterodactylModule } from '../pterodactyl/pterodactyl.module';
import { SecretsModule } from '../secrets/secrets.module';
import { InstanceSyncHandler } from './instance-sync.handler';
import { ResourcesCollectHandler } from './resources-collect.handler';
import { ServerSyncHandler } from './server-sync.handler';

@Module({
  imports: [PterodactylModule, SecretsModule],
  providers: [InstanceSyncHandler, ServerSyncHandler, ResourcesCollectHandler],
  exports: [InstanceSyncHandler, ServerSyncHandler, ResourcesCollectHandler],
})
export class HandlersModule {}
