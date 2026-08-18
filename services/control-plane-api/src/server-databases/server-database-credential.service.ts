import { Injectable, NotFoundException } from '@nestjs/common';
import { PterodactylServerDatabaseDto } from '@pterocontrol/pterodactyl-sdk';
import { SecretsService } from '@pterocontrol/secrets';
import { PrismaService } from '../prisma/prisma.service';

export interface ResolvedDatabaseCredential {
  host: string;
  port: number;
  databaseName: string;
  username: string;
  password: string;
}

/**
 * Persists the plaintext MySQL password Pterodactyl hands back exactly once
 * (at database create/rotate-password time) so DatabaseGatewayService can
 * connect again later without re-asking Pterodactyl (which never returns it
 * again) or the user (the alternative explicitly rejected in favour of this
 * one - see IMPLEMENTATION_STATUS.md). Encrypted with the same
 * SecretsService/AES-256-GCM as InstanceCredential; resolve() is the only
 * place the plaintext exists in memory, and only for the duration of the
 * gateway query that requested it.
 */
@Injectable()
export class ServerDatabaseCredentialService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly secrets: SecretsService,
  ) {}

  async upsert(
    tenantId: string,
    serverId: string,
    database: PterodactylServerDatabaseDto,
  ): Promise<void> {
    if (database.password === null) {
      return;
    }
    const ciphertext = Uint8Array.from(this.secrets.encrypt(database.password));
    await this.prisma.serverDatabaseCredential.upsert({
      where: {
        serverId_pterodactylDatabaseId: {
          serverId,
          pterodactylDatabaseId: database.id,
        },
      },
      create: {
        tenantId,
        serverId,
        pterodactylDatabaseId: database.id,
        host: database.host,
        port: database.port,
        databaseName: database.name,
        username: database.username,
        ciphertext,
      },
      update: {
        host: database.host,
        port: database.port,
        databaseName: database.name,
        username: database.username,
        ciphertext,
      },
    });
  }

  async remove(serverId: string, pterodactylDatabaseId: string): Promise<void> {
    await this.prisma.serverDatabaseCredential.deleteMany({
      where: { serverId, pterodactylDatabaseId },
    });
  }

  async resolve(
    tenantId: string,
    serverId: string,
    pterodactylDatabaseId: string,
  ): Promise<ResolvedDatabaseCredential> {
    const credential = await this.prisma.serverDatabaseCredential.findFirst({
      where: { tenantId, serverId, pterodactylDatabaseId },
    });
    if (!credential) {
      throw new NotFoundException(
        'No stored credential for this database - create it or rotate its password through the Databases endpoint first',
      );
    }
    return {
      host: credential.host,
      port: credential.port,
      databaseName: credential.databaseName,
      username: credential.username,
      password: this.secrets.decrypt(Buffer.from(credential.ciphertext)),
    };
  }
}
