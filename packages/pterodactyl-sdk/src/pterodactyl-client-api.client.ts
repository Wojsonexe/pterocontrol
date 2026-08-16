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

// Same provenance caveat as the DTOs above - real, publicly documented
// Client API v1 shapes for Schedules/Allocations/Databases/Activity, not
// verified against this repo's Flutter app (none of the four have any
// REST wiring there at all - confirmed by direct code search, not
// assumed).
export interface PterodactylScheduleTaskDto {
  id: number;
  sequenceId: number;
  action: 'command' | 'power' | 'backup';
  payload: string;
  timeOffset: number;
  isQueued: boolean;
}

export interface PterodactylScheduleDto {
  id: number;
  name: string;
  cron: {
    dayOfWeek: string;
    dayOfMonth: string;
    month: string;
    hour: string;
    minute: string;
  };
  isActive: boolean;
  isProcessing: boolean;
  onlyWhenOnline: boolean;
  lastRunAt: string | null;
  nextRunAt: string | null;
  createdAt: string;
  updatedAt: string;
  tasks: PterodactylScheduleTaskDto[];
}

export interface CreateScheduleOptions {
  name: string;
  minute: string;
  hour: string;
  dayOfMonth: string;
  month: string;
  dayOfWeek: string;
  isActive?: boolean;
  onlyWhenOnline?: boolean;
}

export interface CreateScheduleTaskOptions {
  action: 'command' | 'power' | 'backup';
  payload: string;
  timeOffset: number;
}

export interface PterodactylAllocationDto {
  id: number;
  ip: string;
  ipAlias: string | null;
  port: number;
  notes: string | null;
  isDefault: boolean;
}

export interface PterodactylServerDatabaseDto {
  id: string;
  host: string;
  port: number;
  name: string;
  username: string;
  connectionsFrom: string;
  maxConnections: number;
  password: string | null;
}

export interface PterodactylActivityLogDto {
  id: string;
  batch: string | null;
  event: string;
  isApi: boolean;
  ip: string | null;
  description: string | null;
  timestamp: string;
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

interface RawTaskAttributes {
  id: number;
  sequence_id: number;
  action: 'command' | 'power' | 'backup';
  payload: string;
  time_offset: number;
  is_queued: boolean;
}

interface RawScheduleAttributes {
  id: number;
  name: string;
  cron: {
    day_of_week: string;
    day_of_month: string;
    month: string;
    hour: string;
    minute: string;
  };
  is_active: boolean;
  is_processing: boolean;
  only_when_online: boolean;
  last_run_at: string | null;
  next_run_at: string | null;
  created_at: string;
  updated_at: string;
  relationships?: {
    tasks?: { data: { attributes: RawTaskAttributes }[] };
  };
}

interface RawScheduleEnvelope {
  attributes: RawScheduleAttributes;
}

interface RawScheduleListEnvelope {
  data: RawScheduleEnvelope[];
}

interface RawTaskEnvelope {
  attributes: RawTaskAttributes;
}

function isRawScheduleEnvelope(value: unknown): value is RawScheduleEnvelope {
  if (typeof value !== 'object' || value === null || !('attributes' in value)) {
    return false;
  }
  const { attributes } = value;
  return typeof attributes === 'object' && attributes !== null && 'cron' in attributes;
}

function isRawScheduleListEnvelope(value: unknown): value is RawScheduleListEnvelope {
  return (
    typeof value === 'object' && value !== null && 'data' in value && Array.isArray(value.data)
  );
}

function isRawTaskEnvelope(value: unknown): value is RawTaskEnvelope {
  if (typeof value !== 'object' || value === null || !('attributes' in value)) {
    return false;
  }
  const { attributes } = value;
  return typeof attributes === 'object' && attributes !== null && 'action' in attributes;
}

function toTaskDto(raw: RawTaskAttributes): PterodactylScheduleTaskDto {
  return {
    id: raw.id,
    sequenceId: raw.sequence_id,
    action: raw.action,
    payload: raw.payload,
    timeOffset: raw.time_offset,
    isQueued: raw.is_queued,
  };
}

function toScheduleDto(raw: RawScheduleEnvelope): PterodactylScheduleDto {
  const { attributes } = raw;
  return {
    id: attributes.id,
    name: attributes.name,
    cron: {
      dayOfWeek: attributes.cron.day_of_week,
      dayOfMonth: attributes.cron.day_of_month,
      month: attributes.cron.month,
      hour: attributes.cron.hour,
      minute: attributes.cron.minute,
    },
    isActive: attributes.is_active,
    isProcessing: attributes.is_processing,
    onlyWhenOnline: attributes.only_when_online,
    lastRunAt: attributes.last_run_at,
    nextRunAt: attributes.next_run_at,
    createdAt: attributes.created_at,
    updatedAt: attributes.updated_at,
    tasks: (attributes.relationships?.tasks?.data ?? []).map((t) => toTaskDto(t.attributes)),
  };
}

interface RawAllocationAttributes {
  id: number;
  ip: string;
  ip_alias: string | null;
  port: number;
  notes: string | null;
  is_default: boolean;
}

interface RawAllocationEnvelope {
  attributes: RawAllocationAttributes;
}

interface RawAllocationListEnvelope {
  data: RawAllocationEnvelope[];
}

function isRawAllocationEnvelope(value: unknown): value is RawAllocationEnvelope {
  if (typeof value !== 'object' || value === null || !('attributes' in value)) {
    return false;
  }
  const { attributes } = value;
  return typeof attributes === 'object' && attributes !== null && 'ip' in attributes;
}

function isRawAllocationListEnvelope(value: unknown): value is RawAllocationListEnvelope {
  return (
    typeof value === 'object' && value !== null && 'data' in value && Array.isArray(value.data)
  );
}

function toAllocationDto(raw: RawAllocationEnvelope): PterodactylAllocationDto {
  const { attributes } = raw;
  return {
    id: attributes.id,
    ip: attributes.ip,
    ipAlias: attributes.ip_alias,
    port: attributes.port,
    notes: attributes.notes,
    isDefault: attributes.is_default,
  };
}

interface RawServerDatabaseAttributes {
  id: string;
  host: { address: string; port: number };
  name: string;
  username: string;
  connections_from: string;
  max_connections: number;
  relationships?: { password?: { attributes: { password: string } } };
}

interface RawServerDatabaseEnvelope {
  attributes: RawServerDatabaseAttributes;
}

interface RawServerDatabaseListEnvelope {
  data: RawServerDatabaseEnvelope[];
}

function isRawServerDatabaseEnvelope(value: unknown): value is RawServerDatabaseEnvelope {
  if (typeof value !== 'object' || value === null || !('attributes' in value)) {
    return false;
  }
  const { attributes } = value;
  return typeof attributes === 'object' && attributes !== null && 'connections_from' in attributes;
}

function isRawServerDatabaseListEnvelope(
  value: unknown,
): value is RawServerDatabaseListEnvelope {
  return (
    typeof value === 'object' && value !== null && 'data' in value && Array.isArray(value.data)
  );
}

function toServerDatabaseDto(raw: RawServerDatabaseEnvelope): PterodactylServerDatabaseDto {
  const { attributes } = raw;
  return {
    id: attributes.id,
    host: attributes.host.address,
    port: attributes.host.port,
    name: attributes.name,
    username: attributes.username,
    connectionsFrom: attributes.connections_from,
    maxConnections: attributes.max_connections,
    password: attributes.relationships?.password?.attributes.password ?? null,
  };
}

interface RawActivityLogAttributes {
  id: string;
  batch: string | null;
  event: string;
  is_api: boolean;
  ip: string | null;
  description: string | null;
  timestamp: string;
}

interface RawActivityLogEnvelope {
  attributes: RawActivityLogAttributes;
}

interface RawActivityLogListEnvelope {
  data: RawActivityLogEnvelope[];
}

function isRawActivityLogListEnvelope(value: unknown): value is RawActivityLogListEnvelope {
  return (
    typeof value === 'object' && value !== null && 'data' in value && Array.isArray(value.data)
  );
}

function toActivityLogDto(raw: RawActivityLogEnvelope): PterodactylActivityLogDto {
  const { attributes } = raw;
  return {
    id: attributes.id,
    batch: attributes.batch,
    event: attributes.event,
    isApi: attributes.is_api,
    ip: attributes.ip,
    description: attributes.description,
    timestamp: attributes.timestamp,
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

  async listSchedules(
    baseUrl: string,
    apiKey: string,
    serverIdentifier: string,
  ): Promise<PterodactylScheduleDto[]> {
    const raw = await this.http.get(
      baseUrl,
      `/api/client/servers/${serverIdentifier}/schedules`,
      apiKey,
    );
    if (!isRawScheduleListEnvelope(raw)) {
      throw new PterodactylUnexpectedResponseError(
        'Expected a {data: [{attributes: {...}}]} envelope from the schedules list endpoint',
      );
    }
    return raw.data.map(toScheduleDto);
  }

  async createSchedule(
    baseUrl: string,
    apiKey: string,
    serverIdentifier: string,
    options: CreateScheduleOptions,
  ): Promise<PterodactylScheduleDto> {
    const raw = await this.http.post(
      baseUrl,
      `/api/client/servers/${serverIdentifier}/schedules`,
      apiKey,
      {
        name: options.name,
        minute: options.minute,
        hour: options.hour,
        day_of_month: options.dayOfMonth,
        month: options.month,
        day_of_week: options.dayOfWeek,
        is_active: options.isActive ?? true,
        only_when_online: options.onlyWhenOnline ?? false,
      },
    );
    if (!isRawScheduleEnvelope(raw)) {
      throw new PterodactylUnexpectedResponseError(
        'Expected a {attributes: {...}} envelope from the create-schedule endpoint',
      );
    }
    return toScheduleDto(raw);
  }

  async getSchedule(
    baseUrl: string,
    apiKey: string,
    serverIdentifier: string,
    scheduleId: number,
  ): Promise<PterodactylScheduleDto> {
    const raw = await this.http.get(
      baseUrl,
      `/api/client/servers/${serverIdentifier}/schedules/${scheduleId}`,
      apiKey,
    );
    if (!isRawScheduleEnvelope(raw)) {
      throw new PterodactylUnexpectedResponseError(
        'Expected a {attributes: {...}} envelope from the schedule details endpoint',
      );
    }
    return toScheduleDto(raw);
  }

  async deleteSchedule(
    baseUrl: string,
    apiKey: string,
    serverIdentifier: string,
    scheduleId: number,
  ): Promise<void> {
    await this.http.delete(
      baseUrl,
      `/api/client/servers/${serverIdentifier}/schedules/${scheduleId}`,
      apiKey,
    );
  }

  async createScheduleTask(
    baseUrl: string,
    apiKey: string,
    serverIdentifier: string,
    scheduleId: number,
    options: CreateScheduleTaskOptions,
  ): Promise<PterodactylScheduleTaskDto> {
    const raw = await this.http.post(
      baseUrl,
      `/api/client/servers/${serverIdentifier}/schedules/${scheduleId}/tasks`,
      apiKey,
      { action: options.action, payload: options.payload, time_offset: options.timeOffset },
    );
    if (!isRawTaskEnvelope(raw)) {
      throw new PterodactylUnexpectedResponseError(
        'Expected a {attributes: {...}} envelope from the create-task endpoint',
      );
    }
    return toTaskDto(raw.attributes);
  }

  async deleteScheduleTask(
    baseUrl: string,
    apiKey: string,
    serverIdentifier: string,
    scheduleId: number,
    taskId: number,
  ): Promise<void> {
    await this.http.delete(
      baseUrl,
      `/api/client/servers/${serverIdentifier}/schedules/${scheduleId}/tasks/${taskId}`,
      apiKey,
    );
  }

  async listAllocations(
    baseUrl: string,
    apiKey: string,
    serverIdentifier: string,
  ): Promise<PterodactylAllocationDto[]> {
    const raw = await this.http.get(
      baseUrl,
      `/api/client/servers/${serverIdentifier}/network/allocations`,
      apiKey,
    );
    if (!isRawAllocationListEnvelope(raw)) {
      throw new PterodactylUnexpectedResponseError(
        'Expected a {data: [{attributes: {...}}]} envelope from the allocations list endpoint',
      );
    }
    return raw.data.map(toAllocationDto);
  }

  async createAllocation(
    baseUrl: string,
    apiKey: string,
    serverIdentifier: string,
  ): Promise<PterodactylAllocationDto> {
    const raw = await this.http.post(
      baseUrl,
      `/api/client/servers/${serverIdentifier}/network/allocations`,
      apiKey,
      undefined,
    );
    if (!isRawAllocationEnvelope(raw)) {
      throw new PterodactylUnexpectedResponseError(
        'Expected a {attributes: {...}} envelope from the create-allocation endpoint',
      );
    }
    return toAllocationDto(raw);
  }

  async setAllocationNotes(
    baseUrl: string,
    apiKey: string,
    serverIdentifier: string,
    allocationId: number,
    notes: string,
  ): Promise<PterodactylAllocationDto> {
    const raw = await this.http.post(
      baseUrl,
      `/api/client/servers/${serverIdentifier}/network/allocations/${allocationId}`,
      apiKey,
      { notes },
    );
    if (!isRawAllocationEnvelope(raw)) {
      throw new PterodactylUnexpectedResponseError(
        'Expected a {attributes: {...}} envelope from the update-allocation endpoint',
      );
    }
    return toAllocationDto(raw);
  }

  async setPrimaryAllocation(
    baseUrl: string,
    apiKey: string,
    serverIdentifier: string,
    allocationId: number,
  ): Promise<void> {
    await this.http.post(
      baseUrl,
      `/api/client/servers/${serverIdentifier}/network/allocations/${allocationId}/primary`,
      apiKey,
      undefined,
    );
  }

  async deleteAllocation(
    baseUrl: string,
    apiKey: string,
    serverIdentifier: string,
    allocationId: number,
  ): Promise<void> {
    await this.http.delete(
      baseUrl,
      `/api/client/servers/${serverIdentifier}/network/allocations/${allocationId}`,
      apiKey,
    );
  }

  async listServerDatabases(
    baseUrl: string,
    apiKey: string,
    serverIdentifier: string,
  ): Promise<PterodactylServerDatabaseDto[]> {
    const raw = await this.http.get(
      baseUrl,
      `/api/client/servers/${serverIdentifier}/databases`,
      apiKey,
    );
    if (!isRawServerDatabaseListEnvelope(raw)) {
      throw new PterodactylUnexpectedResponseError(
        'Expected a {data: [{attributes: {...}}]} envelope from the databases list endpoint',
      );
    }
    return raw.data.map(toServerDatabaseDto);
  }

  async createServerDatabase(
    baseUrl: string,
    apiKey: string,
    serverIdentifier: string,
    databaseName: string,
    remote = '%',
  ): Promise<PterodactylServerDatabaseDto> {
    const raw = await this.http.post(
      baseUrl,
      `/api/client/servers/${serverIdentifier}/databases`,
      apiKey,
      { database: databaseName, remote },
    );
    if (!isRawServerDatabaseEnvelope(raw)) {
      throw new PterodactylUnexpectedResponseError(
        'Expected a {attributes: {...}} envelope from the create-database endpoint',
      );
    }
    return toServerDatabaseDto(raw);
  }

  async rotateServerDatabasePassword(
    baseUrl: string,
    apiKey: string,
    serverIdentifier: string,
    databaseId: string,
  ): Promise<PterodactylServerDatabaseDto> {
    const raw = await this.http.post(
      baseUrl,
      `/api/client/servers/${serverIdentifier}/databases/${databaseId}/rotate-password`,
      apiKey,
      undefined,
    );
    if (!isRawServerDatabaseEnvelope(raw)) {
      throw new PterodactylUnexpectedResponseError(
        'Expected a {attributes: {...}} envelope from the rotate-database-password endpoint',
      );
    }
    return toServerDatabaseDto(raw);
  }

  async deleteServerDatabase(
    baseUrl: string,
    apiKey: string,
    serverIdentifier: string,
    databaseId: string,
  ): Promise<void> {
    await this.http.delete(
      baseUrl,
      `/api/client/servers/${serverIdentifier}/databases/${databaseId}`,
      apiKey,
    );
  }

  async listActivity(
    baseUrl: string,
    apiKey: string,
    serverIdentifier: string,
  ): Promise<PterodactylActivityLogDto[]> {
    const raw = await this.http.get(
      baseUrl,
      `/api/client/servers/${serverIdentifier}/activity`,
      apiKey,
    );
    if (!isRawActivityLogListEnvelope(raw)) {
      throw new PterodactylUnexpectedResponseError(
        'Expected a {data: [{attributes: {...}}]} envelope from the activity endpoint',
      );
    }
    return raw.data.map(toActivityLogDto);
  }
}
