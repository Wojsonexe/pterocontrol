import { Reflector } from '@nestjs/core';
import { IS_PUBLIC_KEY } from '../auth/decorators/public.decorator';
import { MetricsController } from './metrics.controller';

describe('MetricsController', () => {
  it('is marked @Public() - Prometheus cannot present a Bearer token', () => {
    const reflector = new Reflector();
    expect(reflector.get<boolean>(IS_PUBLIC_KEY, MetricsController)).toBe(true);
  });
});
