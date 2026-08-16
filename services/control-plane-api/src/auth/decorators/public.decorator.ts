import { SetMetadata } from '@nestjs/common';

export const IS_PUBLIC_KEY = 'isPublic';

/**
 * Opts a route (or whole controller) out of the global JwtAuthGuard.
 * Secure-by-default: everything requires a valid Bearer token unless
 * explicitly marked @Public().
 */
export const Public = (): ReturnType<typeof SetMetadata> =>
  SetMetadata(IS_PUBLIC_KEY, true);
