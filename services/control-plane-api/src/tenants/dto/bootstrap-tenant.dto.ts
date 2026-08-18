import { IsEmail, IsString, MinLength } from 'class-validator';

export class BootstrapTenantDto {
  @IsString()
  @MinLength(2)
  tenantName!: string;

  @IsEmail()
  ownerEmail!: string;

  @IsString()
  @MinLength(8)
  ownerPassword!: string;
}
