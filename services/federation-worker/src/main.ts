import 'reflect-metadata';
import { Logger } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';

/**
 * No HTTP server - createApplicationContext() gives full Nest DI without
 * @nestjs/platform-express. enableShutdownHooks() wires SIGTERM/SIGINT to
 * app.close(), which runs every module's onModuleDestroy (closes the
 * RabbitMQ channel/connection, disconnects Prisma) - the channel closing
 * cleanly makes RabbitMQ requeue any delivered-but-unacked message rather
 * than lose it, which is exactly the "worker restart must not lose
 * messages" requirement.
 */
async function bootstrap(): Promise<void> {
  const logger = new Logger('bootstrap');
  const app = await NestFactory.createApplicationContext(AppModule);
  app.enableShutdownHooks();

  logger.log('federation-worker started');
}

void bootstrap();
