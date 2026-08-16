import { BadGatewayException, Injectable } from '@nestjs/common';
import { QueryResult as MySqlQueryResult, RowDataPacket } from 'mysql2/promise';
import { AuditService } from '../audit/audit.service';
import { ServerDatabaseCredentialService } from '../server-databases/server-database-credential.service';
import { MySqlConnectionFactory } from './mysql-connection.factory';
import { validateSql } from './sql-guard';

// Hard cap on rows returned to the client/stored in AuditLog metadata.
// Note this truncates AFTER the driver has already buffered the full
// result set in memory (mysql2/promise's query() is not a streaming
// cursor) - a genuinely huge unbounded SELECT can still cost worker
// memory before truncation kicks in. Combined with the per-query timeout
// below this bounds worst-case impact but is not a hard memory guarantee;
// disclosed here rather than oversold.
const MAX_ROWS = 500;
const QUERY_TIMEOUT_MS = 10_000;
// Audit metadata should never grow unbounded on a pathological input.
const MAX_SQL_IN_AUDIT_LOG = 2000;

export interface QueryResult {
  kind: 'rows' | 'write';
  columns?: string[];
  rows?: Record<string, unknown>[];
  rowCount?: number;
  truncated?: boolean;
  affectedRows?: number;
}

/**
 * Direct SQL execution against a server's Pterodactyl-provisioned MySQL
 * database - distinct from server-databases (which only calls Pterodactyl's
 * management endpoints, never touches the database itself). Scope decided
 * explicitly by the user: full DML (SELECT/INSERT/UPDATE/DELETE), no DDL,
 * password persisted encrypted rather than re-requested every time - see
 * IMPLEMENTATION_STATUS.md for the decision record. RBAC-gated to
 * owner/admin at the controller (raw SQL is a high-privilege action).
 */
@Injectable()
export class DatabaseGatewayService {
  constructor(
    private readonly credentialStore: ServerDatabaseCredentialService,
    private readonly connectionFactory: MySqlConnectionFactory,
    private readonly auditService: AuditService,
  ) {}

  async execute(
    tenantId: string,
    actorId: string,
    serverId: string,
    databaseId: string,
    sql: string,
  ): Promise<QueryResult> {
    validateSql(sql);
    const credential = await this.credentialStore.resolve(tenantId, serverId, databaseId);

    const connection = await this.connectionFactory.connect({
      host: credential.host,
      port: credential.port,
      user: credential.username,
      password: credential.password,
      database: credential.databaseName,
    });

    try {
      const [result] = await connection.query({ sql, timeout: QUERY_TIMEOUT_MS });
      const parsed = this.toQueryResult(result);
      await this.auditService.record({
        tenantId,
        actorId,
        action: 'database_gateway.query',
        targetType: 'server',
        targetId: serverId,
        result: 'success',
        metadata: {
          databaseId,
          sql: sql.slice(0, MAX_SQL_IN_AUDIT_LOG),
          ...(parsed.kind === 'rows'
            ? { rowCount: parsed.rowCount, truncated: parsed.truncated }
            : { affectedRows: parsed.affectedRows }),
        },
      });
      return parsed;
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      await this.auditService.record({
        tenantId,
        actorId,
        action: 'database_gateway.query',
        targetType: 'server',
        targetId: serverId,
        result: 'error',
        metadata: { databaseId, sql: sql.slice(0, MAX_SQL_IN_AUDIT_LOG), message },
      });
      throw new BadGatewayException(`Query failed: ${message}`);
    } finally {
      await connection.end().catch(() => undefined);
    }
  }

  // sql-guard rejects multi-statement input, so a single query() call here
  // only ever returns either a row array (SELECT) or a single result header
  // (INSERT/UPDATE/DELETE) - never the OkPacket[]/RowDataPacket[][] shapes
  // mysql2's type covers for the multi-statement case.
  private toQueryResult(result: MySqlQueryResult): QueryResult {
    if (Array.isArray(result)) {
      const rows = result as RowDataPacket[];
      const truncated = rows.length > MAX_ROWS;
      const limited = truncated ? rows.slice(0, MAX_ROWS) : rows;
      return {
        kind: 'rows',
        columns: limited.length > 0 ? Object.keys(limited[0]) : [],
        rows: limited,
        rowCount: limited.length,
        truncated,
      };
    }
    return { kind: 'write', affectedRows: result.affectedRows };
  }
}
