import { randomUUID } from 'node:crypto';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { PrismaFavoriteRepository } from '../src/infrastructure/database/prisma-favorite-repository.js';
import { PrismaRatingRepository } from '../src/infrastructure/database/prisma-rating-repository.js';
import {
  disconnectDatabase,
  getDatabase,
} from '../src/infrastructure/database/prisma.js';
import type { Track } from '../src/modules/catalog/domain/music-provider.js';

describe.skipIf(!process.env.TEST_DATABASE_URL)(
  'favoritos y calificaciones con PostgreSQL real',
  () => {
    const suffix = randomUUID().replaceAll('-', '').slice(0, 11);
    const prefix = `preferences-test-${suffix}`;
    const favorites = new PrismaFavoriteRepository();
    const ratings = new PrismaRatingRepository();
    let ownerA = '';
    let ownerB = '';
    const track: Track = {
      id: `youtube:${suffix}`,
      source: 'youtube',
      sourceId: suffix,
      title: 'Pista de integración',
      artistName: 'Mysic Test',
      durationSeconds: 180,
      thumbnailUrl: null,
    };

    beforeAll(async () => {
      process.env.DATABASE_URL = process.env.TEST_DATABASE_URL;
      const [a, b] = await Promise.all([
        getDatabase().user.create({
          data: { firebaseUid: `${prefix}-a`, displayName: 'Cuenta A' },
        }),
        getDatabase().user.create({
          data: { firebaseUid: `${prefix}-b`, displayName: 'Cuenta B' },
        }),
      ]);
      ownerA = a.id;
      ownerB = b.id;
    });

    afterAll(async () => {
      try {
        await getDatabase().user.deleteMany({
          where: { firebaseUid: { startsWith: prefix } },
        });
        await getDatabase().track.deleteMany({
          where: { source: 'youtube', sourceId: suffix },
        });
      } finally {
        await disconnectDatabase();
      }
    });

    it('impide favoritos duplicados y aísla cada propietario', async () => {
      await favorites.upsert(ownerA, track);
      await favorites.upsert(ownerA, track);
      expect(await favorites.find(ownerA, 'youtube', suffix)).not.toBeNull();
      expect(await favorites.find(ownerB, 'youtube', suffix)).toBeNull();
      const stored = await getDatabase().track.findUniqueOrThrow({
        where: { source_sourceId: { source: 'youtube', sourceId: suffix } },
      });
      expect(
        await getDatabase().favorite.count({
          where: { userId: ownerA, trackId: stored.id },
        }),
      ).toBe(1);
      expect(await favorites.delete(ownerB, 'youtube', suffix)).toBe(false);
    });

    it('mantiene una calificación por usuario y recalcula el promedio', async () => {
      expect(await ratings.upsert(ownerA, track, 4)).toEqual({
        myScore: 4,
        averageScore: 4,
        ratingCount: 1,
      });
      expect(await ratings.upsert(ownerB, track, 2)).toEqual({
        myScore: 2,
        averageScore: 3,
        ratingCount: 2,
      });
      expect(await ratings.upsert(ownerB, track, 5)).toEqual({
        myScore: 5,
        averageScore: 4.5,
        ratingCount: 2,
      });
      expect((await ratings.get(ownerA, 'youtube', suffix)).myScore).toBe(4);
      const stored = await getDatabase().track.findUniqueOrThrow({
        where: { source_sourceId: { source: 'youtube', sourceId: suffix } },
      });
      await expect(
        getDatabase().rating.create({
          data: { userId: ownerA, trackId: stored.id, score: 6 },
        }),
      ).rejects.toBeTruthy();
    });

    it('habilita RLS y elimina preferencias en cascada', async () => {
      const rows = await getDatabase().$queryRaw<
        { relname: string; relrowsecurity: boolean }[]
      >`SELECT c.relname, c.relrowsecurity
        FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'mysic'
        AND c.relname IN ('favorites', 'ratings')`;
      expect(rows).toHaveLength(2);
      expect(rows.every((row) => row.relrowsecurity)).toBe(true);
      await getDatabase().user.delete({ where: { id: ownerA } });
      expect(
        await getDatabase().favorite.count({ where: { userId: ownerA } }),
      ).toBe(0);
      expect(
        await getDatabase().rating.count({ where: { userId: ownerA } }),
      ).toBe(0);
    });
  },
);
