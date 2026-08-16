import { PterodactylPowerSignal } from '@pterocontrol/pterodactyl-sdk';
import { IsIn } from 'class-validator';

const POWER_SIGNALS: PterodactylPowerSignal[] = ['start', 'stop', 'restart', 'kill'];

export class PowerActionDto {
  @IsIn(POWER_SIGNALS)
  action!: PterodactylPowerSignal;
}
