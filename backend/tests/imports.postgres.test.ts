import { randomUUID } from 'node:crypto';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import request from 'supertest';
import { createApp } from '../src/app.js';
import { PrismaImportRepository } from '../src/infrastructure/database/prisma-import-repository.js';
import {
  getDatabase,
  disconnectDatabase,
} from '../src/infrastructure/database/prisma.js';
import type { Track } from '../src/modules/catalog/domain/music-provider.js';

describe.skipIf(!process.env.TEST_DATABASE_URL)(
  'importaciones con PostgreSQL',
  () => {
    const repository = new PrismaImportRepository();
    const prefix = 'import-test-' + randomUUID();
    const sourcePrefix = randomUUID().replaceAll('-', '').slice(0, 8);
    const tracks: Track[] = Array.from({ length: 500 }, (_, index) => {
      const sourceId = sourcePrefix + index.toString().padStart(3, '0');
      return {
        id: 'youtube:' + sourceId,
        source: 'youtube',
        sourceId,
        title: 'Canción ' + index,
        artistName: 'Artista',
        durationSeconds: 200,
        thumbnailUrl: null,
      };
    });
    let owner = '';
    let other = '';
    beforeAll(async () => {
      process.env.DATABASE_URL = process.env.TEST_DATABASE_URL;
      owner = (
        await getDatabase().user.create({
          data: { firebaseUid: prefix, displayName: 'A' },
        })
      ).id;
      other = (
        await getDatabase().user.create({
          data: { firebaseUid: prefix + '-b', displayName: 'B' },
        })
      ).id;
    });
    afterAll(async () => {
      await getDatabase().user.deleteMany({
        where: { firebaseUid: { startsWith: prefix } },
      });
      await getDatabase().track.deleteMany({
        where: { source: 'youtube', sourceId: { startsWith: sourcePrefix } },
      });
      await disconnectDatabase();
    });

    async function prepare(count = 3) {
      return repository.prepare(
        owner,
        {
          id: randomUUID(),
          name: 'Importada',
          sourceIds: tracks.slice(0, count).map((track) => track.sourceId),
        },
        randomUUID(),
      );
    }

    it('reanuda el borrador, valida fingerprint y aísla usuarios en las rutas', async () => {
      const value = await prepare();
      const input = {
        id: value.id,
        name: value.name,
        sourceIds: value.items.map((item) => item.sourceId),
      };
      expect(
        (await repository.prepare(owner, input, value.fingerprint)).id,
      ).toBe(value.id);
      await expect(
        repository.prepare(owner, input, 'changed'),
      ).rejects.toMatchObject({ status: 409 });
      await expect(
        repository.prepare(other, input, value.fingerprint),
      ).rejects.toMatchObject({ status: 404 });
      const app = createApp({
        importRepository: repository,
        tokenVerifier: {
          async verify(token) {
            return { firebaseUid: token, provider: 'google.com' };
          },
        },
      });
      for (const url of ['', '/resolve', '/confirm']) {
        const response = url
          ? await request(app)
              .post('/api/v1/imports/youtube-music/' + value.id + url)
              .auth(prefix + '-b', { type: 'bearer' })
              .send(url === '/resolve' ? { indices: [0] } : {})
          : await request(app)
              .get('/api/v1/imports/youtube-music/' + value.id)
              .auth(prefix + '-b', { type: 'bearer' });
        expect(response.status).toBe(404);
      }
      expect(
        (
          await request(app)
            .delete('/api/v1/imports/youtube-music/' + value.id)
            .auth(prefix + '-b', { type: 'bearer' })
        ).status,
      ).toBe(404);
      expect(await repository.list(other)).toEqual([]);
    });

    it('fusiona lotes concurrentes y conserva una resolución exitosa', async () => {
      const value = await prepare();
      await Promise.all([
        repository.merge(owner, value.id, [
          {
            index: 0,
            item: {
              sourceId: tracks[0]!.sourceId,
              status: 'ready',
              track: tracks[0]!,
            },
          },
        ]),
        repository.merge(owner, value.id, [
          {
            index: 1,
            item: { sourceId: tracks[1]!.sourceId, status: 'unavailable' },
          },
        ]),
      ]);
      await repository.merge(owner, value.id, [
        { index: 0, item: { sourceId: tracks[0]!.sourceId, status: 'retry' } },
      ]);
      expect(
        (await repository.find(owner, value.id))?.items.map(
          (item) => item.status,
        ),
      ).toEqual(['ready', 'unavailable', 'pending']);
      await expect(repository.confirm(owner, value.id)).rejects.toMatchObject({
        status: 409,
        code: 'IMPORT_PENDING',
      });
      expect(
        await getDatabase().playlist.count({ where: { userId: owner } }),
      ).toBe(0);
    });

    it('confirma simultáneamente una sola playlist privada y omite errores', async () => {
      const value = await prepare();
      await repository.merge(owner, value.id, [
        {
          index: 0,
          item: {
            sourceId: tracks[0]!.sourceId,
            status: 'ready',
            track: tracks[0]!,
          },
        },
        {
          index: 1,
          item: { sourceId: tracks[1]!.sourceId, status: 'unavailable' },
        },
        { index: 2, item: { sourceId: tracks[2]!.sourceId, status: 'retry' } },
      ]);
      const [a, b] = await Promise.all([
        repository.confirm(owner, value.id),
        repository.confirm(owner, value.id),
      ]);
      expect(a.playlistId).toBe(b.playlistId);
      expect(a.items).toEqual([]);
      expect(a.savedCount).toBe(1);
      expect(a.skippedCount).toBe(2);
      const playlist = await getDatabase().playlist.findUniqueOrThrow({
        where: { id: a.playlistId! },
        include: { tracks: true },
      });
      expect(playlist.visibility).toBe('PRIVATE');
      expect(playlist.tracks.map((item) => item.position)).toEqual([0]);
      expect(
        await getDatabase().favorite.count({ where: { userId: owner } }),
      ).toBe(0);
      expect(
        await getDatabase().listeningHistory.count({
          where: { userId: owner },
        }),
      ).toBe(0);
      await getDatabase().playlist.delete({ where: { id: a.playlistId! } });
      const repeat = await repository.confirm(owner, value.id);
      expect(repeat.confirmedAt).not.toBeNull();
      expect(repeat.playlistId).toBeNull();
      expect(
        (await repository.merge(owner, value.id, [])).confirmedAt,
      ).not.toBeNull();
    });

    it('guarda 500 posiciones incluyendo repeticiones y persiste entre clientes', async () => {
      const chosen = tracks.map((track, index) =>
        index === 499 ? tracks[0]! : track,
      );
      const value = await repository.prepare(
        owner,
        {
          id: randomUUID(),
          name: '500 pistas',
          sourceIds: chosen.map((track) => track.sourceId),
        },
        randomUUID(),
      );
      await repository.merge(
        owner,
        value.id,
        chosen.map((track, index) => ({
          index,
          item: { sourceId: track.sourceId, status: 'ready', track },
        })),
      );
      const saved = await repository.confirm(owner, value.id);
      const rows = await getDatabase().playlistTrack.findMany({
        where: { playlistId: saved.playlistId! },
        orderBy: { position: 'asc' },
      });
      expect(rows).toHaveLength(500);
      expect(rows.map((row) => row.position)).toEqual(
        Array.from({ length: 500 }, (_, index) => index),
      );
      expect(rows[0]?.trackId).toBe(rows[499]?.trackId);
      await disconnectDatabase();
      expect(
        (await new PrismaImportRepository().find(owner, value.id))?.playlistId,
      ).toBe(saved.playlistId);
    }, 30_000);

    it('mantiene una sola preparación concurrente y rechaza listas vacías tras revisar', async () => {
      const input = {
        id: randomUUID(),
        name: 'Ausencias',
        sourceIds: [tracks[0]!.sourceId],
      };
      const [a, b] = await Promise.all([
        repository.prepare(owner, input, 'same'),
        repository.prepare(owner, input, 'same'),
      ]);
      expect(a.id).toBe(b.id);
      await repository.merge(owner, a.id, [
        {
          index: 0,
          item: { sourceId: tracks[0]!.sourceId, status: 'unavailable' },
        },
      ]);
      const before = await getDatabase().playlist.count({
        where: { userId: owner },
      });
      await expect(repository.confirm(owner, a.id)).rejects.toMatchObject({
        code: 'IMPORT_EMPTY',
        status: 409,
      });
      expect(
        await getDatabase().playlist.count({ where: { userId: owner } }),
      ).toBe(before);
    });

    it('recorre preparación, revisión y confirmación por HTTP hasta la playlist normal', async () => {
      const app = createApp({
        importRepository: repository,
        musicProvider: {
          async search() {
            return [];
          },
          async getTrack(sourceId) {
            return tracks.find((track) => track.sourceId === sourceId) ?? null;
          },
          async resolvePlayback() {
            return { mode: 'unavailable', reason: 'test' };
          },
        },
        tokenVerifier: {
          async verify(token) {
            return { firebaseUid: token, provider: 'google.com' };
          },
        },
      });
      const path = '/api/v1/imports/youtube-music';
      const id = randomUUID();
      const input = {
        id,
        name: 'Desde Takeout',
        sourceIds: [tracks[1]!.sourceId, tracks[0]!.sourceId],
      };
      const prepared = await request(app)
        .post(path)
        .auth(prefix, { type: 'bearer' })
        .send(input);
      expect(prepared.status).toBe(200);
      const review = await request(app)
        .post(path + '/' + id + '/resolve')
        .auth(prefix, { type: 'bearer' })
        .send({ indices: [0, 1] });
      expect(
        review.body.items.map((item: { status: string }) => item.status),
      ).toEqual(['ready', 'ready']);
      const confirmed = await request(app)
        .post(path + '/' + id + '/confirm')
        .auth(prefix, { type: 'bearer' })
        .send({});
      expect(confirmed.status).toBe(200);
      const detail = await request(app)
        .get('/api/v1/playlists/' + confirmed.body.playlistId)
        .auth(prefix, { type: 'bearer' });
      expect(detail.status).toBe(200);
      expect(
        detail.body.tracks.map(
          (item: { track: { sourceId: string } }) => item.track.sourceId,
        ),
      ).toEqual(input.sourceIds);
      expect(
        (
          await request(app)
            .get('/api/v1/playlists/' + confirmed.body.playlistId)
            .auth(prefix + '-b', { type: 'bearer' })
        ).status,
      ).toBe(404);
    });

    it('permite descartar un borrador propio y conserva comprobantes confirmados', async () => {
      const value = await prepare(1);
      await expect(repository.discard(other, value.id)).rejects.toMatchObject({
        status: 404,
      });
      await repository.discard(owner, value.id);
      expect(await repository.find(owner, value.id)).toBeNull();
      const completed = await prepare(1);
      await repository.merge(owner, completed.id, [
        {
          index: 0,
          item: {
            sourceId: tracks[0]!.sourceId,
            status: 'ready',
            track: tracks[0]!,
          },
        },
      ]);
      await repository.confirm(owner, completed.id);
      await expect(
        repository.discard(owner, completed.id),
      ).rejects.toMatchObject({ status: 409 });
      expect(
        (await repository.find(owner, completed.id))?.confirmedAt,
      ).not.toBeNull();
    });

    it('purga borradores caducados y mantiene RLS activa', async () => {
      const value = await prepare();
      await getDatabase().musicImport.update({
        where: { id: value.id },
        data: { expiresAt: new Date(0) },
      });
      await expect(repository.confirm(owner, value.id)).rejects.toMatchObject({
        status: 404,
      });
      await repository.list(owner);
      expect(await repository.find(owner, value.id)).toBeNull();
      const rows = await getDatabase().$queryRaw<
        { relrowsecurity: boolean }[]
      >`SELECT relrowsecurity FROM pg_class WHERE oid = 'mysic.music_imports'::regclass`;
      expect(rows[0]?.relrowsecurity).toBe(true);
    });

    it('libera el límite de 20 borradores al descartar uno', async () => {
      const limitedUser = (
        await getDatabase().user.create({
          data: { firebaseUid: prefix + '-limits', displayName: 'Límite' },
        })
      ).id;
      const input = () => ({
        id: randomUUID(),
        name: 'Lista',
        sourceIds: [tracks[0]!.sourceId],
      });
      const ids: string[] = [];
      for (let index = 0; index < 20; index++) {
        ids.push(
          (await repository.prepare(limitedUser, input(), randomUUID())).id,
        );
      }
      expect(await repository.list(limitedUser)).toHaveLength(20);
      await expect(
        repository.prepare(limitedUser, input(), randomUUID()),
      ).rejects.toMatchObject({ status: 429 });
      await repository.discard(limitedUser, ids[0]!);
      await expect(
        repository.prepare(limitedUser, input(), randomUUID()),
      ).resolves.toMatchObject({ name: 'Lista' });
    });

    it('revierte íntegramente si falla una escritura intermedia', async () => {
      const value = await prepare(1);
      const badTrack = { ...tracks[0]!, title: 'x'.repeat(501) };
      await repository.merge(owner, value.id, [
        {
          index: 0,
          item: {
            sourceId: badTrack.sourceId,
            status: 'ready',
            track: badTrack,
          },
        },
      ]);
      const before = await getDatabase().playlist.count({
        where: { userId: owner },
      });
      await expect(repository.confirm(owner, value.id)).rejects.toThrow();
      expect(
        await getDatabase().playlist.count({ where: { userId: owner } }),
      ).toBe(before);
      expect((await repository.find(owner, value.id))?.confirmedAt).toBeNull();
    });
  },
);
