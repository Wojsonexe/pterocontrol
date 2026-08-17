import { Module } from '@nestjs/common';
import {
  parseTrustedOrigins,
  PterodactylApplicationApiClient,
  PterodactylClientApiClient,
  PterodactylHttpClient,
  SsrfValidatorService,
} from '@pterocontrol/pterodactyl-sdk';

/**
 * Same Federation Layer primitives as control-plane-api's own
 * PterodactylModule - one implementation in @pterocontrol/pterodactyl-sdk,
 * this is just this process's DI wiring for it (see that module's doc
 * comment for the full rationale, including why TRUSTED_PTERODACTYL_
 * ORIGINS is read from process.env directly here too).
 */
@Module({
  providers: [
    {
      provide: SsrfValidatorService,
      useFactory: () =>
        new SsrfValidatorService(
          parseTrustedOrigins(process.env.TRUSTED_PTERODACTYL_ORIGINS),
        ),
    },
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
