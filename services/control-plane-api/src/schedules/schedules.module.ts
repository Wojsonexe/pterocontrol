import { Module } from '@nestjs/common';
import { AuditModule } from '../audit/audit.module';
import { PterodactylModule } from '../pterodactyl/pterodactyl.module';
import { ServersModule } from '../servers/servers.module';
import { SchedulesController } from './schedules.controller';
import { SchedulesService } from './schedules.service';

@Module({
  imports: [ServersModule, PterodactylModule, AuditModule],
  controllers: [SchedulesController],
  providers: [SchedulesService],
})
export class SchedulesModule {}
