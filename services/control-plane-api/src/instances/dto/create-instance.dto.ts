import { IsOptional, IsString, IsUrl, MinLength } from 'class-validator';

export class CreateInstanceDto {
  @IsString()
  @MinLength(1)
  name!: string;

  // First line of defense (scheme allowlist) - the real SSRF check
  // (private/loopback/link-local IP resolution) happens in
  // SsrfValidatorService, not here; DTO validators can't do DNS lookups.
  @IsUrl({ require_protocol: true, protocols: ['https'] })
  baseUrl!: string;

  @IsString()
  @MinLength(1)
  applicationApiKey!: string;

  @IsOptional()
  @IsString()
  clientApiKey?: string;
}
