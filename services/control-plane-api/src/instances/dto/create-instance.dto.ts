import { IsOptional, IsString, IsUrl, MinLength } from 'class-validator';

export class CreateInstanceDto {
  @IsString()
  @MinLength(1)
  name!: string;

  // Only a URL-shape check - the real check (scheme/port/private-IP,
  // including the operator-trusted-origin exception for a private
  // instance) happens in SsrfValidatorService.assertSafeInstanceUrl, not
  // here; DTO validators can't do DNS lookups or read env config. `http`
  // is intentionally allowed at this layer even though the *default*
  // (non-trusted) path still requires https - rejecting it here would
  // make it impossible to register an operator-trusted http:// instance
  // before the request ever reaches the validator that actually knows
  // about the trust exception.
  @IsUrl({ require_protocol: true, protocols: ['http', 'https'] })
  baseUrl!: string;

  @IsString()
  @MinLength(1)
  applicationApiKey!: string;

  @IsOptional()
  @IsString()
  clientApiKey?: string;
}
