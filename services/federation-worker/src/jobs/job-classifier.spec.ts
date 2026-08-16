import { BadRequestException } from '@nestjs/common';
import {
  PterodactylAuthError,
  PterodactylNetworkError,
  PterodactylNotFoundError,
  PterodactylUnexpectedResponseError,
  PterodactylUpstreamError,
} from '@pterocontrol/pterodactyl-sdk';
import { PermanentJobError } from '../errors/permanent-job-error';
import { classifyError } from './job-classifier';

describe('classifyError', () => {
  it.each([
    ['PermanentJobError', new PermanentJobError('instance not found')],
    ['PterodactylAuthError (401/403)', new PterodactylAuthError('bad key')],
    ['PterodactylNotFoundError (404)', new PterodactylNotFoundError('not found')],
    [
      'PterodactylUpstreamError with a 4xx status',
      new PterodactylUpstreamError('unexpected status', 422),
    ],
    [
      'PterodactylUpstreamError with no status (redirect case)',
      new PterodactylUpstreamError('redirect'),
    ],
    ['a NestJS HttpException (e.g. rejected SSRF check)', new BadRequestException('unsafe URL')],
  ])('classifies %s as permanent - never retry', (_label, error) => {
    expect(classifyError(error)).toBe('permanent');
  });

  it.each([
    ['PterodactylNetworkError (timeout/connection refused)', new PterodactylNetworkError('ECONNREFUSED')],
    ['PterodactylUnexpectedResponseError (bad JSON body)', new PterodactylUnexpectedResponseError('not JSON')],
    ['PterodactylUpstreamError with a 502 status', new PterodactylUpstreamError('bad gateway', 502)],
    ['PterodactylUpstreamError with a 503 status', new PterodactylUpstreamError('unavailable', 503)],
    ['PterodactylUpstreamError with a 504 status', new PterodactylUpstreamError('timeout', 504)],
    ['an unrecognized error (safe default)', new Error('unexpected bug')],
  ])('classifies %s as transient - always retry (bounded by MAX_RETRY_ATTEMPTS)', (_label, error) => {
    expect(classifyError(error)).toBe('transient');
  });
});
