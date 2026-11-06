import { randomUUID } from 'node:crypto';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { PrismaPlaylistRepository } from '../src/infrastructure/database/prisma-playlist-repository.js';
import {
  disconnectDatabase,
  getDatabase,
} from '../src/infrastructure/database/prisma.js';
import {
  PlaylistInvalidOrderError,
  type PlaylistInput,
} from '../src/modules/playlists/domain/playlist.js';
import type { Track } from '../src/modules/catalog/domain/music-provider.js';

describe.skipIf(!process.env.TEST_DATABASE_URL)(
  'playlists con PostgreSQL real',
  () => {
    const suffix = randomUUID().replaceAll('-', '').slice(0, 11);
    const prefix = `playlist-test-${suffix}`;
    const repository = new PrismaPlaylistRepository();
    let ownerA = '';
    let ownerB = '';
    let playlistId = '';
    const input: PlaylistInput = {
      name: 'Lista de integración',
      description: 'Persistida en PostgreSQL',
      visibility: 'private',
    };
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

    it('crea, lista y aplica privacidad por propietario', async () => {
      const created = await repository.create(ownerA, input);
      playlistId = created.id;
      expect(created.visibility).toBe('private');
      expect(created.trackCount).toBe(0);
      expect(
        (await repository.listOwned(ownerA)).map((item) => item.id),
      ).toContain(playlistId);
      expect(await repository.findAccessible(ownerB, playlistId)).toBeNull();
      expect(
        await repository.updateOwned(ownerB, playlistId, { name: 'Intrusión' }),
      ).toBeNull();
      const publicPlaylist = await repository.updateOwned(ownerA, playlistId, {
        visibility: 'public',
      });
      expect(publicPlaylist?.visibility).toBe('public');
      expect(
        (await repository.findAccessible(ownerB, playlistId))
          ?.ownedByCurrentUser,
      ).toBe(false);
    });

    it('admite repetidos, mantiene posiciones contiguas y valida el orden completo', async () => {
      const first = await repository.addTrackOwned(
        ownerA,
        playlistId,
        track,
        500,
      );
      const second = await repository.addTrackOwned(
        ownerA,
        playlistId,
        track,
        500,
      );
      expect(second?.tracks.map((item) => item.position)).toEqual([0, 1]);
      expect(new Set(second?.tracks.map((item) => item.id)).size).toBe(2);
      const reversedIds = [...(second?.tracks ?? [])]
        .reverse()
        .map((item) => item.id);
      const reordered = await repository.reorderOwned(
        ownerA,
        playlistId,
        reversedIds,
      );
      expect(reordered?.tracks.map((item) => item.id)).toEqual(reversedIds);
      await expect(
        repository.reorderOwned(ownerA, playlistId, [reversedIds[0]!]),
      ).rejects.toBeInstanceOf(PlaylistInvalidOrderError);
      const remaining = await repository.removeTrackOwned(
        ownerA,
        playlistId,
        first!.tracks[0]!.id,
      );
      expect(remaining?.tracks.map((item) => item.position)).toEqual([0]);
    }, 20_000);

    it('elimina en cascada y mantiene RLS en todas las tablas privadas', async () => {
      expect(await repository.deleteOwned(ownerB, playlistId)).toBe(false);
      expect(await repository.deleteOwned(ownerA, playlistId)).toBe(true);
      expect(
        await getDatabase().playlistTrack.count({ where: { playlistId } }),
      ).toBe(0);
      const rows = await getDatabase().$queryRaw<
        { relname: string; relrowsecurity: boolean }[]
      >`SELECT c.relname, c.relrowsecurity
        FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'mysic'
        AND c.relname IN ('tracks', 'playlists', 'playlist_tracks')`;
      expect(rows).toHaveLength(3);
      expect(rows.every((row) => row.relrowsecurity)).toBe(true);
    });
  },
);
