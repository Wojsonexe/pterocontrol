import { Module } from '@nestjs/common';
import { EventsModule } from '../events/events.module';
import { PterodactylModule } from '../pterodactyl/pterodactyl.module';
import { SecretsModule } from '../secrets/secrets.module';
import { InstancesController } from './instances.controller';
import { InstancesService } from './instances.service';

@Module({
  imports: [SecretsModule, PterodactylModule, EventsModule],
  controllers: [InstancesController],
  providers: [InstancesService],
  exports: [InstancesService],
})
export class InstancesModule {}
