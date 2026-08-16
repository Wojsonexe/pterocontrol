import { Injectable } from '@nestjs/common';
import {
  PterodactylHttpClient,
  PterodactylUnexpectedResponseError,
} from './pterodactyl-http.client';

export interface PterodactylResourceUsageDto {
  currentState: string;
  isSuspended: boolean;
  cpuAbsolutePercent: number;
  memoryBytes: number;
  diskBytes: number;
  networkRxBytes: number;
  networkTxBytes: number;
  uptimeMs: number;
}

export type PterodactylPowerSignal = 'start' | 'stop' | 'restart' | 'kill';

// Field names and shapes follow Pterodactyl's real, publicly documented
// Client API v1 backup contract (application/vnd.pterodactyl.v1+json) -
// NOT verified against this repo's own Flutter app, which has no backup
// implementation at all (its Backups tab is a literal "coming soon"
// placeholder - see server_detail_screen.dart). Same documented-but-
// never-hit-a-live-panel limitation as the rest of this SDK - see
// IMPLEMENTATION_STATUS.md.
export interface PterodactylBackupDto {
  uuid: string;
  name: string;
  ignoredFiles: string[];
  sha256Hash: string | null;
  bytes: number;
  isSuccessful: boolean;
  isLocked: boolean;
  createdAt: string;
  completedAt: string | null;
}

export interface CreateBackupOptions {
  name?: string;
  ignored?: string;
  isLocked?: boolean;
}

// Same provenance caveat as PterodactylBackupDto above - real, publicly
// documented Client API v1 shape, not verified against this repo's own
// Flutter app (its Startup/Environment tab is likewise a "coming soon"
// placeholder - see server_detail_screen.dart).
export interface PterodactylStartupVariableDto {
  name: string;
  description: string;
  envVariable: string;
  defaultValue: string;
  serverValue: string;
  isEditable: boolean;
  rules: string;
}

interface RawResourceEnvelope {
  attributes: {
    current_state: string;
    is_suspended: boolean;
    resources: {
      memory_bytes: number;
      cpu_absolute: number;
      disk_bytes: number;
      network_rx_bytes: number;
      network_tx_bytes: number;
      uptime: number;
    };
  };
}

function isRawResourceEnvelope(value: unknown): value is RawResourceEnvelope {
  if (typeof value !== 'object' || value === null || !('attributes' in value)) {
    return false;
  }
  const { attributes } = value;
  return (
    typeof attributes === 'object' &&
    attributes !== null &&
    'resources' in attributes &&
    typeof attributes.resources === 'object'
  );
}

interface RawBackupAttributes {
  uuid: string;
  name: string;
  ignored_files: string[];
  sha256_hash: string | null;
  bytes: number;
  is_successful: boolean;
  is_locked: boolean;
  created_at: string;
  completed_at: string | null;
}

interface RawBackupEnvelope {
  attributes: RawBackupAttributes;
}

interface RawBackupListEnvelope {
  data: RawBackupEnvelope[];
}

interface RawSignedUrlEnvelope {
  attributes: { url: string };
}

function isRawBackupEnvelope(value: unknown): value is RawBackupEnvelope {
  if (typeof value !== 'object' || value === null || !('attributes' in value)) {
    return false;
  }
  const { attributes } = value;
  return (
    typeof attributes === 'object' &&
    attributes !== null &&
    'uuid' in attributes &&
    'is_successful' in attributes
  );
}

function isRawBackupListEnvelope(value: unknown): value is RawBackupListEnvelope {
  return (
    typeof value === 'object' &&
    value !== null &&
    'data' in value &&
    Array.isArray(value.data)
  );
}

function isRawSignedUrlEnvelope(value: unknown): value is RawSignedUrlEnvelope {
  if (typeof value !== 'object' || value === null || !('attributes' in value)) {
    return false;
  }
  const { attributes } = value;
  return typeof attributes === 'object' && attributes !== null && 'url' in attributes;
}

function toBackupDto(raw: RawBackupEnvelope): PterodactylBackupDto {
  const { attributes } = raw;
  return {
    uuid: attributes.uuid,
    name: attributes.name,
    ignoredFiles: attributes.ignored_files,
    sha256Hash: attributes.sha256_hash,
    bytes: attributes.bytes,
    isSuccessful: attributes.is_successful,
    isLocked: attributes.is_locked,
    createdAt: attributes.created_at,
    completedAt: attributes.completed_at,
  };
}

interface RawStartupVariableAttributes {
  name: string;
  description: string;
  env_variable: string;
  default_value: string;
  server_value: string;
  is_editable: boolean;
  rules: string;
}

interface RawStartupVariableEnvelope {
  attributes: RawStartupVariableAttributes;
}

interface RawStartupVariableListEnvelope {
  data: RawStartupVariableEnvelope[];
}

function isRawStartupVariableEnvelope(value: unknown): value is RawStartupVariableEnvelope {
  if (typeof value !== 'object' || value === null || !('attributes' in value)) {
    return false;
  }
  const { attributes } = value;
  return (
    typeof attributes === 'object' &&
    attributes !== null &&
    'env_variable' in attributes &&
    'is_editable' in attributes
  );
}

function isRawStartupVariableListEnvelope(
  value: unknown,
): value is RawStartupVariableListEnvelope {
  return (
    typeof value === 'object' &&
    value !== null &&
    'data' in value &&
    Array.isArray(value.data)
  );
}

function toStartupVariableDto(
  raw: RawStartupVariableEnvelope,
): PterodactylStartupVariableDto {
  const { attributes } = raw;
  return {
    name: attributes.name,
    description: attributes.description,
    envVariable: attributes.env_variable,
    defaultValue: attributes.default_value,
    serverValue: attributes.server_value,
    isEditable: attributes.is_editable,
    rules: attributes.rules,
  };
}

/**
 * Pterodactyl Client API - live per-server resource usage and power
 * actions. Always scoped to the server that owns the API key's session
 * (identifier in the URL is the short Pterodactyl identifier, e.g.
 * "d3aac109" - Server.identifier, not Server.pterodactylUuid). Never
 * bulk - one HTTP call per server, exactly as the real API works (no
 * bulk-resources endpoint exists - see docs/architecture §4).
 */
@Injectable()
export class PterodactylClientApiClient {
  constructor(private readonly http: PterodactylHttpClient) {}

  async getResourceUsage(
    baseUrl: string,
    apiKey: string,
    serverIdentifier: string,
  ): Promise<PterodactylResourceUsageDto> {
    const raw = await this.http.get(
      baseUrl,
      `/api/client/servers/${serverIdentifier}/resources`,
      apiKey,
    );
    if (!isRawResourceEnvelope(raw)) {
      throw new PterodactylUnexpectedResponseError(
        'Expected a {attributes: {current_state, resources: {...}}} envelope from the resources endpoint',
      );
    }

    const { attributes } = raw;
    return {
      currentState: attributes.current_state,
      isSuspended: attributes.is_suspended,
      cpuAbsolutePercent: attributes.resources.cpu_absolute,
      memoryBytes: attributes.resources.memory_bytes,
      diskBytes: attributes.resources.disk_bytes,
      networkRxBytes: attributes.resources.network_rx_bytes,
      networkTxBytes: attributes.resources.network_tx_bytes,
      uptimeMs: attributes.resources.uptime,
    };
  }

  async sendPowerAction(
    baseUrl: string,
    apiKey: string,
    serverIdentifier: string,
    signal: PterodactylPowerSignal,
  ): Promise<void> {
    await this.http.post(
      baseUrl,
      `/api/client/servers/${serverIdentifier}/power`,
      apiKey,
      { signal },
    );
  }

  async listBackups(
    baseUrl: string,
    apiKey: string,
    serverIdentifier: string,
  ): Promise<PterodactylBackupDto[]> {
    const raw = await this.http.get(
      baseUrl,
      `/api/client/servers/${serverIdentifier}/backups`,
      apiKey,
    );
    if (!isRawBackupListEnvelope(raw)) {
      throw new PterodactylUnexpectedResponseError(
        'Expected a {data: [{attributes: {...}}]} envelope from the backups list endpoint',
      );
    }
    return raw.data.map(toBackupDto);
  }

  async createBackup(
    baseUrl: string,
    apiKey: string,
    serverIdentifier: string,
    options: CreateBackupOptions = {},
  ): Promise<PterodactylBackupDto> {
    const raw = await this.http.post(
      baseUrl,
      `/api/client/servers/${serverIdentifier}/backups`,
      apiKey,
      {
        ...(options.name !== undefined ? { name: options.name } : {}),
        ...(options.ignored !== undefined ? { ignored: options.ignored } : {}),
        ...(options.isLocked !== undefined ? { is_locked: options.isLocked } : {}),
      },
    );
    if (!isRawBackupEnvelope(raw)) {
      throw new PterodactylUnexpectedResponseError(
        'Expected a {attributes: {...}} envelope from the create-backup endpoint',
      );
    }
    return toBackupDto(raw);
  }

  async getBackup(
    baseUrl: string,
    apiKey: string,
    serverIdentifier: string,
    backupUuid: string,
  ): Promise<PterodactylBackupDto> {
    const raw = await this.http.get(
      baseUrl,
      `/api/client/servers/${serverIdentifier}/backups/${backupUuid}`,
      apiKey,
    );
    if (!isRawBackupEnvelope(raw)) {
      throw new PterodactylUnexpectedResponseError(
        'Expected a {attributes: {...}} envelope from the backup details endpoint',
      );
    }
    return toBackupDto(raw);
  }

  async getBackupDownloadUrl(
    baseUrl: string,
    apiKey: string,
    serverIdentifier: string,
    backupUuid: string,
  ): Promise<string> {
    const raw = await this.http.get(
      baseUrl,
      `/api/client/servers/${serverIdentifier}/backups/${backupUuid}/download`,
      apiKey,
    );
    if (!isRawSignedUrlEnvelope(raw)) {
      throw new PterodactylUnexpectedResponseError(
        'Expected a {attributes: {url}} envelope from the backup download endpoint',
      );
    }
    return raw.attributes.url;
  }

  async deleteBackup(
    baseUrl: string,
    apiKey: string,
    serverIdentifier: string,
    backupUuid: string,
  ): Promise<void> {
    await this.http.delete(
      baseUrl,
      `/api/client/servers/${serverIdentifier}/backups/${backupUuid}`,
      apiKey,
    );
  }

  async restoreBackup(
    baseUrl: string,
    apiKey: string,
    serverIdentifier: string,
    backupUuid: string,
    truncate = false,
  ): Promise<void> {
    await this.http.post(
      baseUrl,
      `/api/client/servers/${serverIdentifier}/backups/${backupUuid}/restore`,
      apiKey,
      { truncate },
    );
  }

  async toggleBackupLock(
    baseUrl: string,
    apiKey: string,
    serverIdentifier: string,
    backupUuid: string,
  ): Promise<PterodactylBackupDto> {
    const raw = await this.http.post(
      baseUrl,
      `/api/client/servers/${serverIdentifier}/backups/${backupUuid}/lock`,
      apiKey,
      undefined,
    );
    if (!isRawBackupEnvelope(raw)) {
      throw new PterodactylUnexpectedResponseError(
        'Expected a {attributes: {...}} envelope from the backup lock endpoint',
      );
    }
    return toBackupDto(raw);
  }

  async getStartupVariables(
    baseUrl: string,
    apiKey: string,
    serverIdentifier: string,
  ): Promise<PterodactylStartupVariableDto[]> {
    const raw = await this.http.get(
      baseUrl,
      `/api/client/servers/${serverIdentifier}/startup`,
      apiKey,
    );
    if (!isRawStartupVariableListEnvelope(raw)) {
      throw new PterodactylUnexpectedResponseError(
        'Expected a {data: [{attributes: {...}}]} envelope from the startup endpoint',
      );
    }
    return raw.data.map(toStartupVariableDto);
  }

  async updateStartupVariable(
    baseUrl: string,
    apiKey: string,
    serverIdentifier: string,
    key: string,
    value: string,
  ): Promise<PterodactylStartupVariableDto> {
    const raw = await this.http.put(
      baseUrl,
      `/api/client/servers/${serverIdentifier}/startup/variable`,
      apiKey,
      { key, value },
    );
    if (!isRawStartupVariableEnvelope(raw)) {
      throw new PterodactylUnexpectedResponseError(
        'Expected a {attributes: {...}} envelope from the update-startup-variable endpoint',
      );
    }
    return toStartupVariableDto(raw);
  }
}
