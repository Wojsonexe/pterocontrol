import { IsIn, IsInt, IsString, Min, MinLength } from 'class-validator';

const TASK_ACTIONS = ['command', 'power', 'backup'] as const;
export type ScheduleTaskAction = (typeof TASK_ACTIONS)[number];

export class CreateScheduleTaskDto {
  @IsIn(TASK_ACTIONS)
  action!: ScheduleTaskAction;

  @IsString()
  @MinLength(1)
  payload!: string;

  @IsInt()
  @Min(0)
  timeOffset!: number;
}
