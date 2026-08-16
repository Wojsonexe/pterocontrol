export interface EnvironmentVariables {
  DATABASE_URL: string;
  SECRETS_MASTER_KEY: string;
  JWT_SECRET: string;
  PORT?: string;
  NODE_ENV?: string;
}

const REQUIRED_KEYS: (keyof EnvironmentVariables)[] = [
  'DATABASE_URL',
  'SECRETS_MASTER_KEY',
  'JWT_SECRET',
];

/**
 * Fail-fast env validation, wired into ConfigModule.forRoot({ validate }).
 * Aggregates every missing required variable into one clear startup error
 * instead of each consumer (SecretsService, JwtModule, ...) throwing its
 * own error the first time it happens to be instantiated.
 */
export function validateEnv(
  config: Record<string, unknown>,
): EnvironmentVariables {
  const missing = REQUIRED_KEYS.filter((key) => !config[key]);
  if (missing.length > 0) {
    throw new Error(
      `Missing required environment variable(s): ${missing.join(', ')}`,
    );
  }

  return config as unknown as EnvironmentVariables;
}
