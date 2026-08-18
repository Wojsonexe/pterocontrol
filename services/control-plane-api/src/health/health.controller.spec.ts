import { Test, TestingModule } from '@nestjs/testing';
import { RabbitMqConnectionService } from '@pterocontrol/rabbitmq';
import { HealthController } from './health.controller';
import { PrismaService } from '../prisma/prisma.service';

describe('HealthController', () => {
  let controller: HealthController;
  const prismaMock = { $queryRaw: jest.fn() };
  const rabbitmqMock = { isConnected: jest.fn() };

  beforeEach(async () => {
    prismaMock.$queryRaw.mockReset();
    rabbitmqMock.isConnected.mockReset().mockReturnValue(true);

    const module: TestingModule = await Test.createTestingModule({
      controllers: [HealthController],
      providers: [
        { provide: PrismaService, useValue: prismaMock },
        { provide: RabbitMqConnectionService, useValue: rabbitmqMock },
      ],
    }).compile();

    controller = module.get<HealthController>(HealthController);
  });

  it('returns an ok status with a valid timestamp', () => {
    const result = controller.check();

    expect(result.status).toBe('ok');
    expect(new Date(result.timestamp).toString()).not.toBe('Invalid Date');
  });

  it('reports ready when the database responds', async () => {
    prismaMock.$queryRaw.mockResolvedValueOnce([{ '?column?': 1 }]);

    const result = await controller.ready();

    expect(result.status).toBe('ok');
  });

  it('reports not ready when the database is unreachable', async () => {
    prismaMock.$queryRaw.mockRejectedValueOnce(new Error('connection refused'));

    await expect(controller.ready()).rejects.toThrow();
  });

  it('reports degraded (not an error) when RabbitMQ is disconnected but the database is fine', async () => {
    prismaMock.$queryRaw.mockResolvedValueOnce([{ '?column?': 1 }]);
    rabbitmqMock.isConnected.mockReturnValue(false);

    const result = await controller.ready();

    expect(result.status).toBe('degraded');
    expect(result.dependencies).toEqual({
      database: 'connected',
      rabbitmq: 'disconnected',
    });
  });
});