import { IsIn } from 'class-validator';
import { PterodactylPowerSignal } from '../../pterodactyl/pterodactyl-client-api.client';

const POWER_SIGNALS: PterodactylPowerSignal[] = ['start', 'stop', 'restart', 'kill'];

export class PowerActionDto {
  @IsIn(POWER_SIGNALS)
  action!: PterodactylPowerSignal;
}
