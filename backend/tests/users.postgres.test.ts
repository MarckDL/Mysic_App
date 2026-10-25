import { randomUUID } from 'node:crypto';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import {
  getDatabase,
  disconnectDatabase,
} from '../src/infrastructure/database/prisma.js';
import { PrismaUserRepository } from '../src/infrastructure/database/prisma-user-repository.js';
import { UserConflictError } from '../src/modules/users/domain/user-repository.js';

// Exclusivamente una base desechable: nunca usa DATABASE_URL de desarrollo.
describe.skipIf(!process.env.TEST_DATABASE_URL)(
  'users con PostgreSQL real',
  () => {
    const prefix = `test-${randomUUID()}`;
    const repository = new PrismaUserRepository();
    beforeAll(() => {
      process.env.DATABASE_URL = process.env.TEST_DATABASE_URL;
    });
    afterAll(async () => {
      try {
        await getDatabase().user.deleteMany({
          where: { firebaseUid: { startsWith: prefix } },
        });
      } finally {
        await disconnectDatabase();
      }
    });
    it('resuelve sync concurrente conservando un único UUID y persiste cambios', async () => {
      const profile = {
        firebaseUid: `${prefix}-a`,
        googleId: `${prefix}-google`,
        displayName: 'Cuenta A',
      };
      const users = await Promise.all(
        Array.from({ length: 8 }, () => repository.sync(profile)),
      );
      expect(new Set(users.map((u) => u.id)).size).toBe(1);
      const updated = await repository.sync({
        ...profile,
        displayName: 'Cuenta actualizada',
      });
      expect(updated.id).toBe(users[0]?.id);
      const b = await repository.sync({ firebaseUid: `${prefix}-b` });
      expect(b.id).not.toBe(updated.id);
      expect(b.displayName).toBe('Usuario Mysic');
      await disconnectDatabase();
      expect(
        (await repository.findByFirebaseUid(profile.firebaseUid))?.displayName,
      ).toBe('Cuenta actualizada');
    });
    it('rechaza google_id duplicado sin fusionar usuarios', async () => {
      await repository.sync({
        firebaseUid: `${prefix}-c`,
        googleId: `${prefix}-shared`,
      });
      await expect(
        repository.sync({
          firebaseUid: `${prefix}-d`,
          googleId: `${prefix}-shared`,
        }),
      ).rejects.toBeInstanceOf(UserConflictError);
      expect(await repository.findByFirebaseUid(`${prefix}-d`)).toBeNull();
    });
    it('mantiene RLS habilitado para los perfiles', async () => {
      const rows = await getDatabase().$queryRaw<{ relrowsecurity: boolean }[]>`
      SELECT relrowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'mysic' AND c.relname = 'users'`;
      expect(rows[0]?.relrowsecurity).toBe(true);
    });
  },
);
