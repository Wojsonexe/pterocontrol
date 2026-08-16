import { Module } from '@nestjs/common';
import {
  PterodactylApplicationApiClient,
  PterodactylClientApiClient,
  PterodactylHttpClient,
  SsrfValidatorService,
} from '@pterocontrol/pterodactyl-sdk';

/**
 * Same Federation Layer primitives as control-plane-api's own
 * PterodactylModule - one implementation in @pterocontrol/pterodactyl-sdk,
 * this is just this process's DI wiring for it (see that module's doc
 * comment for the full rationale).
 */
@Module({
  providers: [
    SsrfValidatorService,
    PterodactylHttpClient,
    PterodactylApplicationApiClient,
    PterodactylClientApiClient,
  ],
  exports: [
    SsrfValidatorService,
    PterodactylHttpClient,
    PterodactylApplicationApiClient,
    PterodactylClientApiClient,
  ],
})
export class PterodactylModule {}
