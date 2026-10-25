import { readFileSync } from 'node:fs';
import { PrismaPg } from '@prisma/adapter-pg';
import { PrismaClient } from '../../generated/prisma/client.js';
import { DatabaseUnavailableError } from '../../modules/users/domain/user-repository.js';

let client: PrismaClient | undefined;

export function getDatabase(): PrismaClient {
  if (client) return client;
  try {
    const connectionString = process.env.DATABASE_URL;
    if (!connectionString) throw new Error();
    const url = new URL(connectionString);
    if (!['postgres:', 'postgresql:'].includes(url.protocol)) throw new Error();
    const local = ['localhost', '127.0.0.1', '::1', '[::1]'].includes(
      url.hostname,
    );
    // pg no debe sobrescribir la verificación TLS por opciones en la URL.
    for (const key of ['sslmode', 'sslcert', 'sslkey', 'sslrootcert']) {
      url.searchParams.delete(key);
    }
    const caFile = process.env.DATABASE_SSL_CA_FILE?.trim();
    const ca = !local && caFile ? readFileSync(caFile, 'utf8') : undefined;
    client = new PrismaClient({
      adapter: new PrismaPg({
        connectionString: url.toString(),
        ssl: local
          ? false
          : { rejectUnauthorized: true, ...(ca ? { ca } : {}) },
        max: 5,
        connectionTimeoutMillis: 10_000,
        query_timeout: 10_000,
      }),
    });
    return client;
  } catch (cause) {
    throw new DatabaseUnavailableError('Configuración de base no disponible', {
      cause,
    });
  }
}

export async function disconnectDatabase(): Promise<void> {
  const current = client;
  client = undefined;
  await current?.$disconnect();
}
