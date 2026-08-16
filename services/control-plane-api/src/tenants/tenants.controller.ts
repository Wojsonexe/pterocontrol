import { Body, Controller, Get, Headers, Post } from '@nestjs/common';
import { Tenant } from '@prisma/client';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { Public } from '../auth/decorators/public.decorator';
import { AuthenticatedUser } from '../auth/guards/jwt-auth.guard';
import { BootstrapTenantDto } from './dto/bootstrap-tenant.dto';
import { BootstrapResult, TenantsService } from './tenants.service';

@Controller('tenants')
export class TenantsController {
  constructor(private readonly tenantsService: TenantsService) {}

  @Public()
  @Post()
  bootstrap(
    @Headers('x-bootstrap-token') token: string | undefined,
    @Body() dto: BootstrapTenantDto,
  ): Promise<BootstrapResult> {
    return this.tenantsService.bootstrap(token, dto);
  }

  @Get('me')
  me(@CurrentUser() user: AuthenticatedUser): Promise<Tenant> {
    return this.tenantsService.findById(user.tenantId);
  }
}
