import { Injectable } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
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
    const payload = { sub: user.id, email: user.email };
    const accessToken = await this.jwtService.signAsync(payload);

    return { accessToken };
  }
}
