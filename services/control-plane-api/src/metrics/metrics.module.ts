import { Module } from '@nestjs/common';
import { PrometheusModule } from '@willsoto/nestjs-prometheus';
import { MetricsController } from './metrics.controller';

/**
 * Default process metrics (CPU, memory, event loop lag, GC, open handles)
 * via prom-client's `collectDefaultMetrics` - exposed at `GET /metrics`.
 * See `MetricsController`'s own doc comment for why that route is
 * `@Public()` and why it must never be reachable outside the private
 * network Prometheus scrapes it from.
 *
 * federation-worker has no metrics endpoint yet - it has no HTTP server
 * to hang one off (see IMPLEMENTATION_STATUS.md, FAZA 9b: "bez HTTP"),
 * and adding one just for /metrics is a separate architectural decision
 * this phase didn't make. Documented gap, not an oversight.
 */
@Module({
  imports: [
    PrometheusModule.register({
      controller: MetricsController,
      defaultMetrics: { enabled: true },
    }),
  ],
})
export class MetricsModule {}
