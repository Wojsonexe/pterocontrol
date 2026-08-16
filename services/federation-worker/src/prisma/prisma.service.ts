import { Injectable, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { PrismaClient } from '@prisma/client';

/**
 * Same generated @prisma/client as control-plane-api (hoisted via npm
 * workspaces, one schema - services/control-plane-api/prisma/schema.prisma
 * - is still the single source of truth; this process never runs its own
 * migrations). A separate PrismaClient instance/connection pool is normal
 * and correct here: this is a different OS process, it cannot share a
 * live client instance with control-plane-api even though both read the
 * same generated types.
 */
@Injectable()
export class PrismaService
  extends PrismaClient
  implements OnModuleInit, OnModuleDestroy
{
  async onModuleInit(): Promise<void> {
    await this.$connect();
  }

  async onModuleDestroy(): Promise<void> {
    await this.$disconnect();
  }
}
