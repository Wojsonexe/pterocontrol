import { PasswordService } from './password.service';

describe('PasswordService', () => {
  const service = new PasswordService();

  it('verifies a password against its own hash', async () => {
    const hash = await service.hash('correct horse battery staple');

    await expect(
      service.verify(hash, 'correct horse battery staple'),
    ).resolves.toBe(true);
  });

  it('rejects an incorrect password', async () => {
    const hash = await service.hash('correct horse battery staple');

    await expect(service.verify(hash, 'wrong password')).resolves.toBe(
      false,
    );
  });

  it('produces a different hash each time (random salt)', async () => {
    const a = await service.hash('same-input');
    const b = await service.hash('same-input');

    expect(a).not.toBe(b);
  });
});