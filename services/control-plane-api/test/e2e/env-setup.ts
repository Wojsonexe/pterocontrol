import * as dotenv from 'dotenv';
import path from 'path';

/**
 * Registered as Jest's `setupFiles` (not `setupFilesAfterEach`) - runs
 * before any test file is even `require`d. That timing matters: a test
 * file's static `import { AppModule } from '...'` gets hoisted and
 * evaluated before any code in the test file's own body runs, and
 * `@Module({ imports: [ConfigModule.forRoot(...)] })`'s decorator call
 * executes at that same import-time, not at `NestFactory`/`Test.
 * createTestingModule` bootstrap time. `ConfigModule.forRoot()` loads
 * `.env` from `process.cwd()` itself (the real dev file) unless
 * `process.env.DATABASE_URL` etc. are already set by the time it runs -
 * so this file's job is to win that race by running first, not to be
 * called from inside `setup-app.ts` after `AppModule` is already
 * imported (that was tried and lost the race - `PrismaClient` connected
 * with the real dev `pterocontrol` credentials instead of the E2E ones).
 */
dotenv.config({ path: path.join(__dirname, '..', '.env.e2e') });
