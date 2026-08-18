import { Module } from '@nestjs/common';
import { PterodactylModule } from '../pterodactyl/pterodactyl.module';
import { ServersModule } from '../servers/servers.module';
import { ActivityController } from './activity.controller';
import { ActivityService } from './activity.service';

@Module({
  imports: [ServersModule, PterodactylModule],
  controllers: [ActivityController],
  providers: [ActivityService],
})
export class ActivityModule {}
