import { Module } from '@nestjs/common';
import { SecretsService } from '@pterocontrol/secrets';

@Module({
  providers: [SecretsService],
  exports: [SecretsService],
})
export class SecretsModule {}
