import { ArgumentsHost, HttpException, HttpStatus } from '@nestjs/common';
import { AllExceptionsFilter } from './all-exceptions.filter';

describe('AllExceptionsFilter', () => {
  let filter: AllExceptionsFilter;
  const jsonMock = jest.fn();
  const statusMock = jest.fn(() => ({ json: jsonMock }));
  const getResponse = jest.fn(() => ({ status: statusMock }));
  const getRequest = jest.fn(() => ({
    method: 'GET',
    originalUrl: '/test',
  }));
  const host = {
    switchToHttp: () => ({ getResponse, getRequest }),
  } as unknown as ArgumentsHost;

  beforeEach(() => {
    filter = new AllExceptionsFilter();
    jsonMock.mockClear();
    statusMock.mockClear();
  });

  it('formats an HttpException using its own status and message', () => {
    filter.catch(new HttpException('Not found', HttpStatus.NOT_FOUND), host);

    expect(statusMock).toHaveBeenCalledWith(404);
    expect(jsonMock).toHaveBeenCalledWith(
      expect.objectContaining({
        statusCode: 404,
        message: 'Not found',
        path: '/test',
      }),
    );
  });

  it('masks unexpected errors as a generic 500 without leaking details', () => {
    filter.catch(new Error('db connection string leaked here'), host);

    expect(statusMock).toHaveBeenCalledWith(500);
    expect(jsonMock).toHaveBeenCalledWith(
      expect.objectContaining({
        statusCode: 500,
        message: 'Internal server error',
      }),
    );
  });

  it('preserves a validation error array from ValidationPipe', () => {
    filter.catch(
      new HttpException(
        { message: ['email must be an email'], error: 'Bad Request', statusCode: 400 },
        HttpStatus.BAD_REQUEST,
      ),
      host,
    );

    expect(jsonMock).toHaveBeenCalledWith(
      expect.objectContaining({
        statusCode: 400,
        message: ['email must be an email'],
      }),
    );
  });
});
