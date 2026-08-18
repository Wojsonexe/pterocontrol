import { Module } from '@nestjs/common';
import { AuditModule } from '../audit/audit.module';
import { PterodactylModule } from '../pterodactyl/pterodactyl.module';
import { ServersModule } from '../servers/servers.module';
import { AllocationsController } from './allocations.controller';
import { AllocationsService } from './allocations.service';

@Module({
  imports: [ServersModule, PterodactylModule, AuditModule],
  controllers: [AllocationsController],
  providers: [AllocationsService],
})
export class AllocationsModule {}
