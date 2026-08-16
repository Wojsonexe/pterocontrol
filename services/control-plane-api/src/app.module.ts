import { Module } from '@nestjs/common';
import { HealthModule } from './health/health.module';
import { SecretsModule } from './secrets/secrets.module';

@Module({
  imports: [HealthModule, SecretsModule],
})
export class AppModule {}
