import { IsBoolean, IsOptional, IsString } from 'class-validator';

export class CreateBackupDto {
  @IsOptional()
  @IsString()
  name?: string;

  // Pterodactyl's own field name is "ignored" (a newline/glob pattern
  // list as a single string), kept as-is here rather than renamed, since
  // this DTO is passed through close to verbatim.
  @IsOptional()
  @IsString()
  ignored?: string;

  @IsOptional()
  @IsBoolean()
  isLocked?: boolean;
}
