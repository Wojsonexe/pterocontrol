import {
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Tenant } from '@prisma/client';
import { PasswordService } from '../auth/password.service';
import { PrismaService } from '../prisma/prisma.service';
import { BootstrapTenantDto } from './dto/bootstrap-tenant.dto';

export interface MembershipContext {
  tenantId: string;
  role: string;
}

export interface BootstrapResult {
  tenant: Tenant;
  owner: { id: string; email: string };
}

@Injectable()
export class TenantsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly passwordService: PasswordService,
    private readonly config: ConfigService,
  ) {}

  /**
   * Creates a Tenant + its first User (owner role) + the Membership
   * linking them, atomically. Gated by BOOTSTRAP_TOKEN (env) rather than
   * left open - self-service tenant creation is explicitly out of scope
   * for MVP (see MVP Implementation Plan §1). If BOOTSTRAP_TOKEN is not
   * configured at all, bootstrap is disabled entirely (safe default).
   */
  async bootstrap(
    providedToken: string | undefined,
    dto: BootstrapTenantDto,
  ): Promise<BootstrapResult> {
    const expectedToken = this.config.get<string>('BOOTSTRAP_TOKEN');
    if (!expectedToken || providedToken !== expectedToken) {
      throw new ForbiddenException('Invalid or missing bootstrap token');
    }

    const passwordHash = await this.passwordService.hash(dto.ownerPassword);

    return this.prisma.$transaction(async (tx) => {
      const tenant = await tx.tenant.create({ data: { name: dto.tenantName } });
      const role = await tx.role.upsert({
        where: { name: 'owner' },
        update: {},
        create: { name: 'owner' },
      });
      const user = await tx.user.create({
        data: { email: dto.ownerEmail, passwordHash },
      });
      await tx.membership.create({
        data: { tenantId: tenant.id, userId: user.id, roleId: role.id },
      });

      return { tenant, owner: { id: user.id, email: user.email } };
    });
  }

  async findById(tenantId: string): Promise<Tenant> {
    const tenant = await this.prisma.tenant.findUnique({
      where: { id: tenantId },
    });
    if (!tenant) {
      throw new NotFoundException('Tenant not found');
    }
    return tenant;
  }

  /**
   * MVP assumption: a user belongs to exactly one tenant (no UI/flow yet
   * for a user to be invited into multiple tenants) - the first
   * membership found is treated as authoritative. Returns null if the
   * user has none, which AuthService.login() treats as a hard failure:
   * a user with no tenant context can't do anything meaningful here.
   */
  async findPrimaryMembership(userId: string): Promise<MembershipContext | null> {
    const membership = await this.prisma.membership.findFirst({
      where: { userId },
      include: { role: true },
      orderBy: { id: 'asc' },
    });
    if (!membership) {
      return null;
    }
    return { tenantId: membership.tenantId, role: membership.role.name };
  }
}
