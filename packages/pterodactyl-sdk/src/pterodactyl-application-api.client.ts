import { Injectable } from '@nestjs/common';
import {
  PterodactylHttpClient,
  PterodactylUnexpectedResponseError,
} from './pterodactyl-http.client';

export interface PterodactylNodeDto {
  id: number;
  name: string;
  fqdn: string;
  memory: number;
  disk: number;
}

export interface PterodactylApplicationServerDto {
  id: number;
  uuid: string;
  identifier: string;
  name: string;
  node: number;
}

interface PaginatedResponse<T> {
  data: { attributes: T }[];
}

function isPaginatedResponse(value: unknown): value is PaginatedResponse<unknown> {
  return (
    typeof value === 'object' &&
    value !== null &&
    Array.isArray((value as { data?: unknown }).data)
  );
}

/**
 * Pterodactyl Application API - admin-level, bulk inventory (nodes,
 * servers). Never used for live resource stats/power actions - that's
 * Client API's job (PterodactylClientApiClient, added alongside real
 * per-server sync). See docs/architecture, §4, for the full split.
 */
@Injectable()
export class PterodactylApplicationApiClient {
  constructor(private readonly http: PterodactylHttpClient) {}

  /** Connectivity + credential check: GET /api/application/nodes?page=1. */
  async testConnection(baseUrl: string, apiKey: string): Promise<void> {
    await this.listNodes(baseUrl, apiKey, 1);
  }

  async listNodes(
    baseUrl: string,
    apiKey: string,
    page = 1,
  ): Promise<PterodactylNodeDto[]> {
    const raw = await this.http.get(
      baseUrl,
      `/api/application/nodes?page=${page}`,
      apiKey,
    );
    return this.unwrapList<PterodactylNodeDto>(raw);
  }

  async listServers(
    baseUrl: string,
    apiKey: string,
    page = 1,
  ): Promise<PterodactylApplicationServerDto[]> {
    const raw = await this.http.get(
      baseUrl,
      `/api/application/servers?page=${page}`,
      apiKey,
    );
    return this.unwrapList<PterodactylApplicationServerDto>(raw);
  }

  private unwrapList<T>(raw: unknown): T[] {
    if (!isPaginatedResponse(raw)) {
      throw new PterodactylUnexpectedResponseError(
        'Expected a Fractal-style {data: [{attributes: ...}]} envelope',
      );
    }
    return raw.data.map((entry) => entry.attributes as T);
  }
}
