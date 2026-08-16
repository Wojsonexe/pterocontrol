import { Injectable } from '@nestjs/common';
import { createCipheriv, createDecipheriv, randomBytes } from 'crypto';

const ALGORITHM = 'aes-256-gcm';
const IV_LENGTH = 12;
const AUTH_TAG_LENGTH = 16;
const KEY_LENGTH = 32;

/**
 * Szyfruje/odszyfrowuje sekrety (klucze API Pterodactyla, hasła baz danych)
 * przed zapisem do Postgresa. Format wyjściowy encrypt(): [iv (12B)][authTag (16B)][ciphertext].
 * Klucz master pochodzi z SECRETS_MASTER_KEY (32 bajty, base64) — nigdy nie jest
 * hardcodowany ani logowany.
 */
@Injectable()
export class SecretsService {
  private readonly key: Buffer;

  constructor() {
    const raw = process.env.SECRETS_MASTER_KEY;
    if (!raw) {
      throw new Error('SECRETS_MASTER_KEY environment variable is not set');
    }

    const key = Buffer.from(raw, 'base64');
    if (key.length !== KEY_LENGTH) {
      throw new Error(
        `SECRETS_MASTER_KEY must decode to ${KEY_LENGTH} bytes, got ${key.length}`,
      );
    }

    this.key = key;
  }

  encrypt(plaintext: string): Buffer {
    const iv = randomBytes(IV_LENGTH);
    const cipher = createCipheriv(ALGORITHM, this.key, iv);
    const ciphertext = Buffer.concat([
      cipher.update(plaintext, 'utf8'),
      cipher.final(),
    ]);
    const authTag = cipher.getAuthTag();

    return Buffer.concat([iv, authTag, ciphertext]);
  }

  decrypt(payload: Buffer): string {
    const iv = payload.subarray(0, IV_LENGTH);
    const authTag = payload.subarray(IV_LENGTH, IV_LENGTH + AUTH_TAG_LENGTH);
    const ciphertext = payload.subarray(IV_LENGTH + AUTH_TAG_LENGTH);

    const decipher = createDecipheriv(ALGORITHM, this.key, iv);
    decipher.setAuthTag(authTag);

    return Buffer.concat([
      decipher.update(ciphertext),
      decipher.final(),
    ]).toString('utf8');
  }
}
