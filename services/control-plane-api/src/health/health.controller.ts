import { Controller, Get, ServiceUnavailableException } from '@nestjs/common';
import { RabbitMqConnectionService } from '@pterocontrol/rabbitmq';
import { Public } from '../auth/decorators/public.decorator';
import { PrismaService } from '../prisma/prisma.service';

interface HealthStatus {
  status: 'ok';
  timestamp: string;
}

interface ReadinessStatus {
  status: 'ok' | 'degraded';
  timestamp: string;
  dependencies: {
    database: 'connected';
    rabbitmq: 'connected' | 'disconnected';
  };
}

@Public()
@Controller('health')
export class HealthController {
  constructor(
    private readonly prisma: PrismaService,
    private readonly rabbitmq: RabbitMqConnectionService,
  ) {}

  @Get()
  check(): HealthStatus {
    return { status: 'ok', timestamp: new Date().toISOString() };
  }

  // Postgres is the only hard dependency (source of truth - see
  // schema.prisma) - unreachable DB means a real 503. RabbitMQ being down
  // degrades queue-dependent features (sync, background resource
  // collection) but must never take the whole API down, so it is reported
  // as `degraded`, not thrown as an error.
  @Get('ready')
  async ready(): Promise<ReadinessStatus> {
    try {
      await this.prisma.$queryRaw`SELECT 1`;
    } catch {
      throw new ServiceUnavailableException('Database is not reachable');
    }

    const rabbitmqConnected = this.rabbitmq.isConnected();
    return {
      status: rabbitmqConnected ? 'ok' : 'degraded',
      timestamp: new Date().toISOString(),
      dependencies: {
        database: 'connected',
        rabbitmq: rabbitmqConnected ? 'connected' : 'disconnected',
      },
    };
  }
}
