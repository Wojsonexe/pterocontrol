import { IsBoolean, IsOptional, IsString, MinLength } from 'class-validator';

export class CreateScheduleDto {
  @IsString()
  @MinLength(1)
  name!: string;

  @IsString()
  minute!: string;

  @IsString()
  hour!: string;

  @IsString()
  dayOfMonth!: string;

  @IsString()
  month!: string;

  @IsString()
  dayOfWeek!: string;

  @IsOptional()
  @IsBoolean()
  isActive?: boolean;

  @IsOptional()
  @IsBoolean()
  onlyWhenOnline?: boolean;
}
