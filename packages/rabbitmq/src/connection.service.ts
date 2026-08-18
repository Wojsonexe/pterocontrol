import { Injectable, Logger, OnModuleDestroy } from '@nestjs/common';
import * as amqp from 'amqplib';
import { setupTopology } from './topology';

const RECONNECT_DELAY_MS = 5_000;

/**
 * Resilient amqplib connection: reconnects automatically on drop,
 * re-asserts the topology on every (re)connect (cheap, idempotent -
 * see topology.ts). getChannel() throws synchronously when the
 * connection is down rather than queueing/blocking - callers (the
 * HTTP layer in control-plane-api) must catch that and return a
 * controlled error, never let the request hang waiting for a broker
 * that might not come back soon.
 */
@Injectable()
export class RabbitMqConnectionService implements OnModuleDestroy {
  private readonly logger = new Logger(RabbitMqConnectionService.name);
  private connection: amqp.ChannelModel | null = null;
  private channel: amqp.Channel | null = null;
  private connecting = false;
  private closedByUs = false;
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null;

  constructor(private readonly url: string) {}

  async connect(): Promise<void> {
    if (this.connecting || this.channel) {
      return;
    }
    this.connecting = true;
    try {
      const connection = await amqp.connect(this.url);
      const channel = await connection.createChannel();
      await setupTopology(channel);
      await channel.prefetch(1);

      connection.on('error', (error) => {
        this.logger.warn(`RabbitMQ connection error: ${String(error)}`);
      });
      connection.on('close', () => {
        this.channel = null;
        this.connection = null;
        if (!this.closedByUs) {
          this.logger.warn(
            'RabbitMQ connection closed unexpectedly - scheduling reconnect',
          );
          this.scheduleReconnect();
        }
      });

      this.connection = connection;
      this.channel = channel;
      this.logger.log('Connected to RabbitMQ, topology asserted');
    } catch (error) {
      this.logger.warn(`Could not connect to RabbitMQ: ${String(error)}`);
      this.scheduleReconnect();
    } finally {
      this.connecting = false;
    }
  }

  private scheduleReconnect(): void {
    if (this.reconnectTimer) {
      return;
    }
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = null;
      void this.connect();
    }, RECONNECT_DELAY_MS);
  }

  getChannel(): amqp.Channel {
    if (!this.channel) {
      throw new Error('RabbitMQ channel is not available (connection down)');
    }
    return this.channel;
  }

  isConnected(): boolean {
    return this.channel !== null;
  }

  async onModuleDestroy(): Promise<void> {
    this.closedByUs = true;
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
    }
    try {
      await this.channel?.close();
      await this.connection?.close();
    } catch {
      // Best-effort on shutdown - nothing useful to do with a close error.
    }
  }
}
