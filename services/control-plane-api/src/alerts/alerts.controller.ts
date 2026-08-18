import { Controller, Get, Query } from '@nestjs/common';
import { Alert } from '@prisma/client';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { AuthenticatedUser } from '../auth/guards/jwt-auth.guard';
import { AlertsService } from './alerts.service';

function parseBoolean(value?: string): boolean | undefined {
  if (value === undefined) return undefined;
  return value === 'true';
}

@Controller('alerts')
export class AlertsController {
  constructor(private readonly alertsService: AlertsService) {}

  @Get()
  findAll(
    @CurrentUser() user: AuthenticatedUser,
    @Query('ruleId') ruleId?: string,
    @Query('serverId') serverId?: string,
    @Query('instanceId') instanceId?: string,
    @Query('active') active?: string,
  ): Promise<Alert[]> {
    return this.alertsService.findAllAlertsForTenant(user.tenantId, {
      ruleId,
      serverId,
      instanceId,
      active: parseBoolean(active),
    });
  }
}
