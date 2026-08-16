import { Module } from '@nestjs/common';
import { PterodactylApplicationApiClient } from './pterodactyl-application-api.client';
import { PterodactylHttpClient } from './pterodactyl-http.client';
import { SsrfValidatorService } from './ssrf-validator.service';

/**
 * The actual "Federation Layer" primitives - everything that knows how
 * to safely talk to a Pterodactyl instance's Application API. Owned
 * independently of InstancesModule/ServersModule (both import this
 * rather than one importing the other's client), so those two stay
 * one-directional (ServersModule -> InstancesModule for credential
 * lookup) without a module cycle.
 */
@Module({
  providers: [SsrfValidatorService, PterodactylHttpClient, PterodactylApplicationApiClient],
  exports: [SsrfValidatorService, PterodactylHttpClient, PterodactylApplicationApiClient],
})
export class PterodactylModule {}
