import { Module } from '@nestjs/common';
import { AuditModule } from '../audit/audit.module';
import { PterodactylModule } from '../pterodactyl/pterodactyl.module';
import { SecretsModule } from '../secrets/secrets.module';
import { ServersModule } from '../servers/servers.module';
import { ServerDatabaseCredentialService } from './server-database-credential.service';
import { ServerDatabasesController } from './server-databases.controller';
import { ServerDatabasesService } from './server-databases.service';

@Module({
  imports: [ServersModule, PterodactylModule, AuditModule, SecretsModule],
  controllers: [ServerDatabasesController],
  providers: [ServerDatabasesService, ServerDatabaseCredentialService],
  exports: [ServerDatabaseCredentialService],
})
export class ServerDatabasesModule {}
