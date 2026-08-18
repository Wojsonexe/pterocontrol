import { Injectable } from '@nestjs/common';
import mysql, { Connection } from 'mysql2/promise';

export interface MySqlConnectionConfig {
  host: string;
  port: number;
  user: string;
  password: string;
  database: string;
}

/**
 * Thin wrapper around mysql2's createConnection so DatabaseGatewayService
 * can be unit-tested without a real MySQL server - the connection itself
 * is only exercised by live Docker-based verification, same split as
 * PterodactylHttpClient vs the SDK clients that use it.
 */
@Injectable()
export class MySqlConnectionFactory {
  connect(config: MySqlConnectionConfig): Promise<Connection> {
    return mysql.createConnection({
      host: config.host,
      port: config.port,
      user: config.user,
      password: config.password,
      database: config.database,
      connectTimeout: 5000,
    });
  }
}
