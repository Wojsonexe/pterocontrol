import { Module } from '@nestjs/common';
import {
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
