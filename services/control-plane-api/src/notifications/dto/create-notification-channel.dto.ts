import { NotificationChannelType } from '@prisma/client';
import { IsEnum, IsUrl } from 'class-validator';

export class CreateNotificationChannelDto {
  // Only WEBHOOK exists today, but the field stays required and
  // enum-validated so the API contract does not have to change shape
  // when a second channel type (e.g. SLACK) is added later.
  @IsEnum(NotificationChannelType)
  type!: NotificationChannelType;

  // First line of defense (scheme allowlist), same reasoning as
  // CreateInstanceDto.baseUrl - the real SSRF check (private/loopback/
  // link-local IP resolution) happens in SsrfValidatorService, both here
  // (immediate feedback) and again by federation-worker right before
  // every send.
  @IsUrl({ require_protocol: true, protocols: ['https'] })
  url!: string;
}
