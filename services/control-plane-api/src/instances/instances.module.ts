import { Module } from '@nestjs/common';
import { SecretsModule } from '../secrets/secrets.module';
import { InstancesController } from './instances.controller';
import { InstancesService } from './instances.service';
import { PterodactylApplicationApiClient } from './pterodactyl-application-api.client';
import { PterodactylHttpClient } from './pterodactyl-http.client';
import { SsrfValidatorService } from './ssrf-validator.service';

@Module({
  imports: [SecretsModule],
  controllers: [InstancesController],
  providers: [
    InstancesService,
    SsrfValidatorService,
    PterodactylHttpClient,
    PterodactylApplicationApiClient,
  ],
  exports: [InstancesService, PterodactylApplicationApiClient],
})
export class InstancesModule {}
