import { ValidationPipe, INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { AppModule } from '../../src/app.module';
import { AllExceptionsFilter } from '../../src/common/filters/all-exceptions.filter';

/**
 * Boots the real `AppModule` against the E2E Postgres/RabbitMQ - the same
 * global pipes/filters `main.ts` applies, so a request through
 * `app.getHttpServer()` behaves exactly like a request to a real running
 * server, just without the `app.listen()` TCP port.
 *
 * `process.env` for the E2E database/secrets is populated by `env-setup.ts`
 * (registered as Jest's `setupFiles`, not called from here) - it has to
 * run before this file's own `import { AppModule }` above is evaluated,
 * since `@Module({ imports: [ConfigModule.forRoot(...)] })` loads the
 * *real* dev `.env` at that import's decorator-evaluation time if nothing
 * has set `DATABASE_URL` first. See `env-setup.ts`'s own doc comment.
 */
export async function createE2eApp(): Promise<INestApplication> {
  const moduleRef = await Test.createTestingModule({
    imports: [AppModule],
  }).compile();

  const app = moduleRef.createNestApplication();
  app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true }));
  app.useGlobalFilters(new AllExceptionsFilter());
  await app.init();
  return app;
}
