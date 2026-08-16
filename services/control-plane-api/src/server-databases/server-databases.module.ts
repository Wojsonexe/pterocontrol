import { Module } from '@nestjs/common';
import { AuditModule } from '../audit/audit.module';
import { PterodactylModule } from '../pterodactyl/pterodactyl.module';
import { ServersModule } from '../servers/servers.module';
import { ServerDatabasesController } from './server-databases.controller';
import { ServerDatabasesService } from './server-databases.service';

@Module({
  imports: [ServersModule, PterodactylModule, AuditModule],
  controllers: [ServerDatabasesController],
  providers: [ServerDatabasesService],
})
export class ServerDatabasesModule {}
