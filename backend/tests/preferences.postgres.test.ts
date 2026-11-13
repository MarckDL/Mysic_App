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
  'favoritos y ratings con PostgreSQL real',
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
      title: 'Pista de preferencias',
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

    it('hace idempotente el favorito concurrente y aísla propietarios', async () => {
      await Promise.all([
        favorites.add(ownerA, track),
        favorites.add(ownerA, track),
      ]);
      expect(await favorites.has(ownerA, track.id)).toBe(true);
      expect(await favorites.has(ownerB, track.id)).toBe(false);
      expect(await favorites.list(ownerA)).toHaveLength(1);
      expect(await favorites.list(ownerB)).toHaveLength(0);
      await favorites.remove(ownerB, track.id);
      expect(await favorites.has(ownerA, track.id)).toBe(true);
    });

    it('mantiene un rating por usuario y calcula promedio y cantidad', async () => {
      expect(await ratings.status(ownerA, track.id)).toEqual({
        myRating: null,
        ratingAverage: null,
        ratingCount: 0,
      });
      await ratings.upsert(ownerA, track, 2);
      const changed = await ratings.upsert(ownerA, track, 4);
      expect(changed).toEqual({
        myRating: 4,
        ratingAverage: 4,
        ratingCount: 1,
      });
      const second = await ratings.upsert(ownerB, track, 5);
      expect(second).toEqual({
        myRating: 5,
        ratingAverage: 4.5,
        ratingCount: 2,
      });
      expect(await ratings.status(ownerA, track.id)).toEqual({
        myRating: 4,
        ratingAverage: 4.5,
        ratingCount: 2,
      });
      expect(
        await getDatabase().rating.count({ where: { userId: ownerA } }),
      ).toBe(1);
    });

    it('aplica CHECK, cascada de usuario y RLS', async () => {
      const storedTrack = await getDatabase().track.findUniqueOrThrow({
        where: {
          source_sourceId: { source: track.source, sourceId: track.sourceId },
        },
        select: { id: true },
      });
      await expect(
        getDatabase().rating.create({
          data: {
            userId: ownerA,
            trackId: storedTrack.id,
            score: 6,
          },
        }),
      ).rejects.toBeTruthy();
      const rows = await getDatabase().$queryRaw<
        { relname: string; relrowsecurity: boolean }[]
      >`SELECT c.relname, c.relrowsecurity
        FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'mysic'
        AND c.relname IN ('favorites', 'ratings')`;
      expect(rows).toHaveLength(2);
      expect(rows.every((row) => row.relrowsecurity)).toBe(true);
      await getDatabase().user.delete({ where: { id: ownerB } });
      expect(
        await getDatabase().rating.count({ where: { userId: ownerB } }),
      ).toBe(0);
    });
  },
);
