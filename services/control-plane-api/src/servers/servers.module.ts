import { Module } from '@nestjs/common';
import { AuditModule } from '../audit/audit.module';
import { EventsModule } from '../events/events.module';
import { InstancesModule } from '../instances/instances.module';
import { PterodactylModule } from '../pterodactyl/pterodactyl.module';
import { SecretsModule } from '../secrets/secrets.module';
import { ServerCredentialResolverService } from './server-credential-resolver.service';
import { ServersController } from './servers.controller';
import { ServersService } from './servers.service';

@Module({
  imports: [InstancesModule, PterodactylModule, SecretsModule, AuditModule, EventsModule],
  controllers: [ServersController],
  providers: [ServersService, ServerCredentialResolverService],
  exports: [ServersService, ServerCredentialResolverService],
})
export class ServersModule {}
