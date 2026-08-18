import { Module } from '@nestjs/common';
import {
  parseTrustedOrigins,
  PterodactylApplicationApiClient,
  PterodactylClientApiClient,
  PterodactylHttpClient,
  SsrfValidatorService,
} from '@pterocontrol/pterodactyl-sdk';

/**
 * The actual "Federation Layer" primitives - everything that knows how
 * to safely talk to a Pterodactyl instance's Application/Client API.
 * The classes themselves live in @pterocontrol/pterodactyl-sdk (shared
 * with federation-worker, which makes the same real outbound calls -
 * one implementation of the SSRF check, not two that can drift apart).
 * This module is just this app's own NestJS DI wiring for them.
 */
@Module({
  providers: [
    {
      provide: SsrfValidatorService,
      // process.env directly, not ConfigService: this module (and the
      // shared @pterocontrol/pterodactyl-sdk package it wires up) has no
      // dependency on @nestjs/config today, and one env var doesn't
      // justify adding one - env.validation.ts's ConfigModule.forRoot
      // has already fail-fast-validated the required vars by the time
      // any provider factory runs, this one is optional regardless.
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
