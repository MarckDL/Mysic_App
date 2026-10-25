import { defineConfig } from 'prisma/config';

export default defineConfig({
  schema: 'prisma/schema.prisma',
  migrations: {
    path: 'prisma/migrations',
  },
  // Los scripts cargan .env con Node. Generate no necesita una base conectada.
  datasource: {
    url: process.env.DIRECT_URL ?? '',
  },
});
