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
}
