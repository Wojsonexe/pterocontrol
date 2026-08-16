import { AlertMetric, AlertOperator } from '@prisma/client';
import {
  IsEnum,
  IsInt,
  IsNumber,
  IsOptional,
  IsString,
  Min,
  MinLength,
} from 'class-validator';

export class CreateAlertRuleDto {
  @IsString()
  @MinLength(1)
  name!: string;

  @IsEnum(AlertMetric)
  metric!: AlertMetric;

  // Cross-field requirements (operator+threshold for the threshold
  // metrics, serverId/instanceId depending on metric) are enforced in
  // AlertsService, not here - class-validator has no clean way to express
  // "required only when metric is X" without a custom validator, and the
  // service already has to do the tenant-ownership check on
  // serverId/instanceId anyway.
  @IsOptional()
  @IsEnum(AlertOperator)
  operator?: AlertOperator;

  @IsOptional()
  @IsNumber()
  threshold?: number;

  @IsOptional()
  @IsString()
  serverId?: string;

  @IsOptional()
  @IsString()
  instanceId?: string;

  @IsOptional()
  @IsInt()
  @Min(0)
  cooldownSeconds?: number;
}
