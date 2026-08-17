export interface EnvironmentVariables {
  DATABASE_URL: string;
  SECRETS_MASTER_KEY: string;
  RABBITMQ_URL: string;
  // Same meaning and value as control-plane-api's own env.validation.ts -
  // both processes must be configured identically or InstanceSyncHandler
  // would trust an origin control-plane-api's InstancesService didn't
  // (or vice versa). See SsrfValidatorService.assertSafeInstanceUrl.
  TRUSTED_PTERODACTYL_ORIGINS?: string;
  NODE_ENV?: string;
}

const REQUIRED_KEYS: (keyof EnvironmentVariables)[] = [
  'DATABASE_URL',
  'SECRETS_MASTER_KEY',
  'RABBITMQ_URL',
];

/**
 * Fail-fast env validation - deliberately a smaller set than
 * control-plane-api's (no JWT_SECRET/BOOTSTRAP_TOKEN: this process never
 * serves HTTP or issues tokens, so those variables are meaningless here).
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
