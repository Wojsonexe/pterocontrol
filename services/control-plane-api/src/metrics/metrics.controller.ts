import { Controller, Get, Res } from '@nestjs/common';
import { PrometheusController } from '@willsoto/nestjs-prometheus';
import type { Response } from 'express';
import { Public } from '../auth/decorators/public.decorator';

/**
 * `GET /metrics` - opted out of the global JwtAuthGuard (@Public()):
 * Prometheus can't present a Bearer token, and this endpoint is not meant
 * to be reachable from outside the private network Prometheus itself runs
 * on. **This is a deployment-topology requirement, not something this
 * code enforces** - see infra/docker-compose.prod.yml and infra/
 * DEPLOYMENT.md: `/metrics` must never be added to the Cloudflare Tunnel's
 * public ingress rules, only scraped by Prometheus over the internal
 * Docker network.
 */
// @Controller()/@Get() are deliberately empty - PrometheusModule.register()
// sets the actual route path via Reflect.defineMetadata("path", ...) on
// this class at registration time (see its own source), matching the
// library's own documented override example exactly.
@Public()
@Controller()
export class MetricsController extends PrometheusController {
  @Get()
  index(@Res({ passthrough: true }) response: Response): Promise<string> {
    return super.index(response);
  }
}
