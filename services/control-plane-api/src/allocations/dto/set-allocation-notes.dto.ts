import { IsString } from 'class-validator';

export class SetAllocationNotesDto {
  @IsString()
  notes!: string;
}
