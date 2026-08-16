import { validateEnv } from './env.validation';

describe('validateEnv', () => {
  const validConfig = {
    DATABASE_URL: 'postgresql://user:pass@localhost:5432/db',
    SECRETS_MASTER_KEY: 'key',
    JWT_SECRET: 'secret',
  };

  it('returns the config unchanged when all required keys are present', () => {
    expect(validateEnv(validConfig)).toEqual(validConfig);
  });

  it('throws listing every missing required key', () => {
    expect(() => validateEnv({ DATABASE_URL: 'x' })).toThrow(
      /SECRETS_MASTER_KEY, JWT_SECRET/,
    );
  });

  it('throws when a required key is present but empty', () => {
    expect(() =>
      validateEnv({ ...validConfig, JWT_SECRET: '' }),
    ).toThrow(/JWT_SECRET/);
  });
});
