import { Module } from '@nestjs/common';
import { AuditModule } from '../audit/audit.module';
import { PterodactylModule } from '../pterodactyl/pterodactyl.module';
import { ServerDatabasesModule } from '../server-databases/server-databases.module';
import { DatabaseGatewayController } from './database-gateway.controller';
import { DatabaseGatewayService } from './database-gateway.service';
import { MySqlConnectionFactory } from './mysql-connection.factory';

@Module({
  imports: [ServerDatabasesModule, AuditModule, PterodactylModule],
  controllers: [DatabaseGatewayController],
  providers: [DatabaseGatewayService, MySqlConnectionFactory],
})
export class DatabaseGatewayModule {}
