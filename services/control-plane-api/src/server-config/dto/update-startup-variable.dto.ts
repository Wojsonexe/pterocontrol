import { IsString, MinLength } from 'class-validator';

export class UpdateStartupVariableDto {
  @IsString()
  @MinLength(1)
  key!: string;

  // Deliberately not further constrained here - Pterodactyl validates
  // the value against the variable's own `rules` string server-side;
  // duplicating that validation logic here would require parsing an
  // arbitrary Laravel validation-rule string, not worth it for this MVP.
  @IsString()
  value!: string;
}
