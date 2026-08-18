import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
  HttpStatus,
  Logger,
} from '@nestjs/common';
import type { Request, Response } from 'express';

interface ErrorResponseBody {
  statusCode: number;
  message: unknown;
  path: string;
  timestamp: string;
}

// Plain number, not the HttpStatus enum member directly - comparing a
// runtime `number` (exception.getStatus()) against an enum member trips
// @typescript-eslint/no-unsafe-enum-comparison; a pre-widened constant
// sidesteps that without an unnecessary-assertion warning either.
const SERVER_ERROR_THRESHOLD: number = HttpStatus.INTERNAL_SERVER_ERROR;

/**
 * Single place every unhandled error passes through: consistent JSON shape
 * for clients, and a server-side log entry for anything that isn't an
 * expected 4xx HttpException (so a bug surfaces in logs, not just as a
 * generic 500 the caller has to guess about).
 */
@Catch()
export class AllExceptionsFilter implements ExceptionFilter {
  private readonly logger = new Logger(AllExceptionsFilter.name);

  catch(exception: unknown, host: ArgumentsHost): void {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse<Response>();
    const request = ctx.getRequest<Request>();

    const isHttpException = exception instanceof HttpException;
    const status: number = isHttpException
      ? exception.getStatus()
      : HttpStatus.INTERNAL_SERVER_ERROR;

    const message = this.extractMessage(exception, isHttpException);

    if (!isHttpException || status >= SERVER_ERROR_THRESHOLD) {
      this.logger.error(
        `${request.method} ${request.originalUrl} -> ${status}`,
        exception instanceof Error ? exception.stack : String(exception),
      );
    }

    const body: ErrorResponseBody = {
      statusCode: status,
      message,
      path: request.originalUrl,
      timestamp: new Date().toISOString(),
    };

    response.status(status).json(body);
  }

  private extractMessage(exception: unknown, isHttpException: boolean): unknown {
    if (isHttpException) {
      const payload = (exception as HttpException).getResponse();
      if (typeof payload === 'object' && payload !== null && 'message' in payload) {
        return payload.message;
      }
      return (exception as HttpException).message;
    }

    // Never leak internal error details (stack traces, DB error text) to
    // the client for unexpected errors - only to the server-side log above.
    return 'Internal server error';
  }
}
