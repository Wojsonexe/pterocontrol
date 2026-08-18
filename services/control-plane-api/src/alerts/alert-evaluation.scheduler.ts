import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { AlertsService } from './alerts.service';

/**
 * Runs a tick after ResourceCollectionScheduler's own EVERY_MINUTE sweep
 * (see servers module) so a rule evaluated this tick has a real chance
 * of seeing a snapshot collected this same minute, not the previous one.
 */
@Injectable()
export class AlertEvaluationScheduler {
  private readonly logger = new Logger(AlertEvaluationScheduler.name);

  constructor(private readonly alertsService: AlertsService) {}

  @Cron(CronExpression.EVERY_MINUTE)
  async evaluate(): Promise<void> {
    try {
      await this.alertsService.evaluate();
    } catch (error) {
      this.logger.warn(`Alert evaluation sweep failed: ${String(error)}`);
    }
  }
}
