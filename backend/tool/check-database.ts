import {
  getDatabase,
  disconnectDatabase,
} from '../src/infrastructure/database/prisma.js';

import { databaseDiagnostic } from '../src/infrastructure/database/database-diagnostic.js';

try {
  await getDatabase().$queryRaw`SELECT 1`;
  console.info('PostgreSQL: conexión Prisma correcta');
} catch (error) {
  console.error(
    'No se pudo conectar mediante Prisma. Revisar DATABASE_URL, red y certificado TLS; no compartir credenciales.',
  );
  console.error(databaseDiagnostic(error));
  process.exitCode = 1;
} finally {
  await disconnectDatabase();
}
