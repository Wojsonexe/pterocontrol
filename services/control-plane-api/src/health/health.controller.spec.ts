import { Test, TestingModule } from '@nestjs/testing';
import { HealthController } from './health.controller';
import { PrismaService } from '../prisma/prisma.service';

describe('HealthController', () => {
  let controller: HealthController;
  const prismaMock = { $queryRaw: jest.fn() };

  beforeEach(async () => {
    prismaMock.$queryRaw.mockReset();

    const module: TestingModule = await Test.createTestingModule({
      controllers: [HealthController],
      providers: [{ provide: PrismaService, useValue: prismaMock }],
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
});