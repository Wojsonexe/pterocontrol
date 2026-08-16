import { Module } from '@nestjs/common';
import { InstancesModule } from '../instances/instances.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { ServersModule } from '../servers/servers.module';
import { AlertEvaluationScheduler } from './alert-evaluation.scheduler';
import { AlertRulesController } from './alert-rules.controller';
import { AlertsController } from './alerts.controller';
import { AlertsService } from './alerts.service';

@Module({
  imports: [InstancesModule, ServersModule, NotificationsModule],
  controllers: [AlertRulesController, AlertsController],
  providers: [AlertsService, AlertEvaluationScheduler],
  exports: [AlertsService],
})
export class AlertsModule {}
