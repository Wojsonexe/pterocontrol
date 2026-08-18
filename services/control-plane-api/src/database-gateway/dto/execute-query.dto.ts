import { IsString, MaxLength, MinLength } from 'class-validator';

export class ExecuteQueryDto {
  @IsString()
  @MinLength(1)
  @MaxLength(10000)
  sql!: string;
}
