import { SecretsService } from './secrets.service';

describe('SecretsService', () => {
  const originalEnv = process.env.SECRETS_MASTER_KEY;

  beforeAll(() => {
    process.env.SECRETS_MASTER_KEY = Buffer.alloc(32, 7).toString('base64');
  });

  afterAll(() => {
    process.env.SECRETS_MASTER_KEY = originalEnv;
  });

  it('decrypts exactly what it encrypted', () => {
    const service = new SecretsService();
    const plaintext = 'ptlc_super_secret_client_api_key';

    const ciphertext = service.encrypt(plaintext);
    const decrypted = service.decrypt(ciphertext);

    expect(decrypted).toBe(plaintext);
  });

  it('produces a different ciphertext each time (random IV)', () => {
    const service = new SecretsService();
    const plaintext = 'same-input';

    const a = service.encrypt(plaintext);
    const b = service.encrypt(plaintext);

    expect(a.equals(b)).toBe(false);
  });

  it('throws if the ciphertext has been tampered with', () => {
    const service = new SecretsService();
    const ciphertext = service.encrypt('sensitive-value');
    ciphertext[ciphertext.length - 1] ^= 0xff;

    expect(() => service.decrypt(ciphertext)).toThrow();
  });
});
