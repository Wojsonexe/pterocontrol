import { IsOptional, IsString, MinLength } from 'class-validator';

export class CreateServerDatabaseDto {
  @IsString()
  @MinLength(1)
  database!: string;

  // Pterodactyl's "connections from" host pattern, e.g. "%" for any host.
  // Optional - PterodactylClientApiClient.createServerDatabase() defaults
  // it to "%" when omitted.
  @IsOptional()
  @IsString()
  remote?: string;
}
