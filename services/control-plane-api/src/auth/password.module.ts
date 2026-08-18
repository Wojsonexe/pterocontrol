import { Module } from '@nestjs/common';
import { PasswordService } from './password.service';

/**
 * Split out of AuthModule so TenantsModule (needed for bootstrap
 * password hashing) doesn't have to import AuthModule, which in turn
 * imports TenantsModule (for login's membership lookup) - that would be
 * a circular module dependency. PasswordService has no dependency on
 * anything auth-specific, so it belongs in its own small module.
 */
@Module({
  providers: [PasswordService],
  exports: [PasswordService],
})
export class PasswordModule {}
