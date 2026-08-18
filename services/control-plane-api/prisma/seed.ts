import { PrismaClient } from '@prisma/client';
import * as argon2 from 'argon2';

const prisma = new PrismaClient();

async function main(): Promise<void> {
  const email = 'dev@pterocontrol.local';
  const passwordHash = await argon2.hash('dev-password-change-me');

  const user = await prisma.user.upsert({
    where: { email },
    update: {},
    create: { email, passwordHash },
  });

  const role = await prisma.role.upsert({
    where: { name: 'owner' },
    update: {},
    create: { name: 'owner' },
  });

  const tenant = await prisma.tenant.upsert({
    where: { id: '00000000-0000-0000-0000-000000000001' },
    update: {},
    create: {
      id: '00000000-0000-0000-0000-000000000001',
      name: 'Dev Tenant',
    },
  });

  const membership = await prisma.membership.upsert({
    where: { tenantId_userId: { tenantId: tenant.id, userId: user.id } },
    update: {},
    create: { tenantId: tenant.id, userId: user.id, roleId: role.id },
  });

  console.log(`Seeded user: ${user.email} (${user.id})`);
  console.log(`Seeded tenant: ${tenant.name} (${tenant.id})`);
  console.log(`Seeded membership: ${membership.id} (role: ${role.name})`);
}

main()
  .catch((error: unknown) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
