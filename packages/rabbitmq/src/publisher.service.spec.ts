import { RabbitMqConnectionService } from './connection.service';
import { createEnvelope } from './envelope';
import { RabbitMqPublisherService } from './publisher.service';

describe('RabbitMqPublisherService', () => {
  const channelMock = { publish: jest.fn() };
  const connectionMock = { getChannel: jest.fn() };
  let publisher: RabbitMqPublisherService;

  beforeEach(() => {
    jest.clearAllMocks();
    connectionMock.getChannel.mockReturnValue(channelMock);
    publisher = new RabbitMqPublisherService(
      connectionMock as unknown as RabbitMqConnectionService,
    );
  });

  it('publishes a persistent message with the envelope as the JSON body', () => {
    channelMock.publish.mockReturnValueOnce(true);
    const envelope = createEnvelope({ tenantId: 't-1', payload: { foo: 'bar' } });

    publisher.publish('cp.federation', 'federation.instance.sync', envelope);

    expect(channelMock.publish).toHaveBeenCalledTimes(1);
    const [exchange, routingKey, content, options] = channelMock.publish.mock.calls[0] as [
      string,
      string,
      Buffer,
      Record<string, unknown>,
    ];
    expect(exchange).toBe('cp.federation');
    expect(routingKey).toBe('federation.instance.sync');
    expect(JSON.parse(content.toString())).toEqual(envelope);
    expect(options.persistent).toBe(true);
    expect(options.messageId).toBe(envelope.jobId);
  });

  it('sets the AMQP expiration property when expirationMs is given (the retry-delay mechanism)', () => {
    channelMock.publish.mockReturnValueOnce(true);
    const envelope = createEnvelope({ tenantId: 't-1', payload: {} });

    publisher.publish('cp.retry', 'federation.instance.sync', envelope, {
      expirationMs: 15_000,
    });

    const [, , , options] = channelMock.publish.mock.calls[0] as [
      string,
      string,
      Buffer,
      Record<string, unknown>,
    ];
    expect(options.expiration).toBe('15000');
  });

  it('propagates the connection error when the broker is unreachable, instead of silently dropping the message', () => {
    connectionMock.getChannel.mockImplementationOnce(() => {
      throw new Error('RabbitMQ channel is not available (connection down)');
    });
    const envelope = createEnvelope({ tenantId: 't-1', payload: {} });

    expect(() =>
      publisher.publish('cp.federation', 'federation.instance.sync', envelope),
    ).toThrow('connection down');
    expect(channelMock.publish).not.toHaveBeenCalled();
  });
});
