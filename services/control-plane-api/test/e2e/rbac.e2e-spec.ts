import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { PasswordService } from '../../src/auth/password.service';
import { PrismaService } from '../../src/prisma/prisma.service';
import { createE2eApp } from './setup-app';

/**
 * The one live-request gap this whole session's manual verification never
 * covered (see IMPLEMENTATION_STATUS.md, "Świadomie NIEkompletne" ->
 * "RBAC nie ma jeszcze prawdziwego testu wielo-rolowego na żywo"):
 * `POST /tenants` bootstrap only ever creates an `owner`, and there is no
 * invite-a-member endpoint yet, so nothing in this codebase has ever sent
 * a real HTTP request as a non-owner role.
 *
 * There being no invite API is exactly why this seeds the `viewer`
 * Membership directly via Prisma rather than through the HTTP API - that
 * part is test setup standing in for a feature that doesn't exist yet,
 * not something this test is trying to verify.
 */
describe('RBAC with a non-owner role (e2e)', () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let passwordService: PasswordService;
  let bootstrapToken: string;

  beforeAll(async () => {
    app = await createE2eApp();
    prisma = app.get(PrismaService);
    passwordService = app.get(PasswordService);
    bootstrapToken = process.env.BOOTSTRAP_TOKEN!;
  });

  afterAll(async () => {
    await app.close();
  });

  async function loginAsViewer(): Promise<string> {
    const suffix = `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 6)}`;
    const tenantName = `E2E RBAC ${suffix}`;
    const ownerEmail = `owner-${suffix}@e2e.test`;
    const ownerPassword = 'a-strong-e2e-password';

    const bootstrap = await request(app.getHttpServer())
      .post('/tenants')
      .set('x-bootstrap-token', bootstrapToken)
      .send({ tenantName, ownerEmail, ownerPassword })
      .expect(201);
    const tenantId = bootstrap.body.tenant.id as string;

    const viewerEmail = `viewer-${suffix}@e2e.test`;
    const viewerPassword = 'a-strong-e2e-password';
    const passwordHash = await passwordService.hash(viewerPassword);

    const role = await prisma.role.upsert({
      where: { name: 'viewer' },
      update: {},
      create: { name: 'viewer' },
    });
    const user = await prisma.user.create({ data: { email: viewerEmail, passwordHash } });
    await prisma.membership.create({ data: { tenantId, userId: user.id, roleId: role.id } });

    const login = await request(app.getHttpServer())
      .post('/auth/login')
      .send({ email: viewerEmail, password: viewerPassword })
      .expect(200);

    expect(login.body.user.email).toBe(viewerEmail);
    return login.body.accessToken as string;
  }

  it('blocks a viewer from a mutating, @Roles(owner,admin)-gated endpoint', async () => {
    const viewerToken = await loginAsViewer();

    const response = await request(app.getHttpServer())
      .post('/instances')
      .set('Authorization', `Bearer ${viewerToken}`)
      .send({ name: 'Should be blocked', baseUrl: 'https://example.com', applicationApiKey: 'ptla_x' })
      .expect(403);

    expect(response.body.statusCode).toBe(403);
  });

  it('still allows a viewer to read a GET endpoint with no @Roles restriction', async () => {
    const viewerToken = await loginAsViewer();

    await request(app.getHttpServer())
      .get('/instances')
      .set('Authorization', `Bearer ${viewerToken}`)
      .expect(200);
  });
});
