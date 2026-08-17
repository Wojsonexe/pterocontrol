import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { createE2eApp } from './setup-app';

/**
 * Exercises the real bootstrap -> login -> authenticated-request flow
 * through a real, running `AppModule` and a real (throwaway) Postgres -
 * no mocks below the HTTP boundary. Each spec file uses a uniquely-named
 * tenant/email so parallel or repeated runs against the same E2E database
 * never collide.
 */
describe('Bootstrap and auth (e2e)', () => {
  let app: INestApplication;

  beforeAll(async () => {
    app = await createE2eApp();
  });

  afterAll(async () => {
    await app.close();
  });

  const uniqueSuffix = Date.now().toString(36);
  const ownerEmail = `owner-${uniqueSuffix}@e2e.test`;
  const ownerPassword = 'a-strong-e2e-password';

  it('rejects bootstrap without the correct x-bootstrap-token', async () => {
    await request(app.getHttpServer())
      .post('/tenants')
      .send({ tenantName: 'E2E Tenant', ownerEmail, ownerPassword })
      .expect(403);
  });

  it('bootstraps a tenant + owner with the correct token', async () => {
    const bootstrapToken = process.env.BOOTSTRAP_TOKEN;
    expect(bootstrapToken).toBeTruthy();

    const response = await request(app.getHttpServer())
      .post('/tenants')
      .set('x-bootstrap-token', bootstrapToken!)
      .send({ tenantName: 'E2E Tenant', ownerEmail, ownerPassword })
      .expect(201);

    expect(response.body.tenant.name).toBe('E2E Tenant');
    expect(response.body.owner.email).toBe(ownerEmail);
  });

  it('rejects login with the wrong password', async () => {
    await request(app.getHttpServer())
      .post('/auth/login')
      .send({ email: ownerEmail, password: 'wrong-password' })
      .expect(401);
  });

  it('logs in with the correct credentials and returns a usable JWT', async () => {
    const response = await request(app.getHttpServer())
      .post('/auth/login')
      .send({ email: ownerEmail, password: ownerPassword })
      .expect(200);

    expect(typeof response.body.accessToken).toBe('string');
    expect(response.body.user.email).toBe(ownerEmail);

    const me = await request(app.getHttpServer())
      .get('/tenants/me')
      .set('Authorization', `Bearer ${response.body.accessToken}`)
      .expect(200);
    expect(me.body.name).toBe('E2E Tenant');
  });

  it('rejects an authenticated route with no token at all', async () => {
    await request(app.getHttpServer()).get('/tenants/me').expect(401);
  });

  it('rejects an authenticated route with a garbage token', async () => {
    await request(app.getHttpServer())
      .get('/tenants/me')
      .set('Authorization', 'Bearer not-a-real-jwt')
      .expect(401);
  });
});
