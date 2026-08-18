import { ForbiddenException, Injectable } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { TenantsService } from '../tenants/tenants.service';
import { UsersService } from '../users/users.service';
import { PasswordService } from './password.service';

export interface SafeUser {
  id: string;
  email: string;
  createdAt: Date;
}

export interface AuthTokens {
  accessToken: string;
}

@Injectable()
export class AuthService {
  constructor(
    private readonly usersService: UsersService,
    private readonly passwordService: PasswordService,
    private readonly jwtService: JwtService,
    private readonly tenantsService: TenantsService,
  ) {}

  async validateUser(
    email: string,
    password: string,
  ): Promise<SafeUser | null> {
    const user = await this.usersService.findByEmail(email);
    if (!user) {
      return null;
    }

    const isValid = await this.passwordService.verify(
      user.passwordHash,
      password,
    );
    if (!isValid) {
      return null;
    }

    return { id: user.id, email: user.email, createdAt: user.createdAt };
  }

  async login(user: SafeUser): Promise<AuthTokens> {
    const membership = await this.tenantsService.findPrimaryMembership(
      user.id,
    );
    if (!membership) {
      // A user with no tenant membership can't do anything meaningful in
      // a multi-tenant system - fail loudly instead of issuing a token
      // that carries no tenant context (which every protected endpoint
      // from FAZA 3 onward requires).
      throw new ForbiddenException('User has no tenant membership');
    }

    const payload = {
      sub: user.id,
      email: user.email,
      tenantId: membership.tenantId,
      role: membership.role,
    };
    const accessToken = await this.jwtService.signAsync(payload);

    return { accessToken };
  }
}
