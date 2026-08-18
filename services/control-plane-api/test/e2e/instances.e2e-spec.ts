import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { createE2eApp } from './setup-app';

/**
 * Real HTTP requests through a real `AppModule`: instance creation, the
 * SSRF guard actually rejecting a private-IP baseUrl (not mocked - a real
 * DNS/IP check runs), and tenant isolation on `GET /instances` between two
 * independently bootstrapped tenants.
 */
describe('Instances (e2e)', () => {
  let app: INestApplication;
  let bootstrapToken: string;

  beforeAll(async () => {
    app = await createE2eApp();
    bootstrapToken = process.env.BOOTSTRAP_TOKEN!;
  });

  afterAll(async () => {
    await app.close();
  });

  async function bootstrapAndLogin(label: string): Promise<{ token: string; tenantName: string }> {
    const suffix = `${label}-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 6)}`;
    const tenantName = `E2E Instances ${suffix}`;
    const email = `${suffix}@e2e.test`;
    const password = 'a-strong-e2e-password';

    await request(app.getHttpServer())
      .post('/tenants')
      .set('x-bootstrap-token', bootstrapToken)
      .send({ tenantName, ownerEmail: email, ownerPassword: password })
      .expect(201);

    const login = await request(app.getHttpServer())
      .post('/auth/login')
      .send({ email, password })
      .expect(200);

    return { token: login.body.accessToken as string, tenantName };
  }

  it('rejects a baseUrl that resolves to a private/loopback address (real SSRF check, no mock)', async () => {
    const { token } = await bootstrapAndLogin('ssrf');

    const response = await request(app.getHttpServer())
      .post('/instances')
      .set('Authorization', `Bearer ${token}`)
      .send({ name: 'Malicious', baseUrl: 'https://127.0.0.1', applicationApiKey: 'ptla_fake' })
      .expect(400);

    expect(response.body.message).toMatch(/loopback|private|disallowed/i);
  });

  it('creates an instance with a valid, publicly-resolvable baseUrl (real connectivity test against a non-Pterodactyl host)', async () => {
    const { token } = await bootstrapAndLogin('create');

    const response = await request(app.getHttpServer())
      .post('/instances')
      .set('Authorization', `Bearer ${token}`)
      .send({ name: 'My Panel', baseUrl: 'https://example.com', applicationApiKey: 'ptla_fake_e2e_key' })
      .expect(201);

    expect(response.body.name).toBe('My Panel');
    // InstancesService.create() tests connectivity synchronously right
    // after persisting (see its own doc comment) - example.com is a real,
    // publicly reachable host but not a real Pterodactyl panel, so the
    // application API probe on it genuinely 404s and the instance is
    // correctly marked UNREACHABLE, not PENDING_SYNC. This is the same
    // real behaviour documented in IMPLEMENTATION_STATUS.md's FAZA 3 -
    // asserting on it here is what caught this test's own first-draft
    // wrong assumption (PENDING_SYNC) rather than a bug in the app.
    expect(response.body.status).toBe('UNREACHABLE');

    const list = await request(app.getHttpServer())
      .get('/instances')
      .set('Authorization', `Bearer ${token}`)
      .expect(200);
    expect(list.body.some((i: { id: string }) => i.id === response.body.id)).toBe(true);
  });

  it('never shows one tenant a different tenant\'s instances', async () => {
    const tenantA = await bootstrapAndLogin('tenant-a');
    const tenantB = await bootstrapAndLogin('tenant-b');

    await request(app.getHttpServer())
      .post('/instances')
      .set('Authorization', `Bearer ${tenantA.token}`)
      .send({ name: 'Tenant A Panel', baseUrl: 'https://example.com', applicationApiKey: 'ptla_a' })
      .expect(201);

    const tenantBList = await request(app.getHttpServer())
      .get('/instances')
      .set('Authorization', `Bearer ${tenantB.token}`)
      .expect(200);

    expect(tenantBList.body).toEqual([]);
  });
});
