import { randomBytes, randomUUID } from 'node:crypto';
import {
  afterAll,
  beforeAll,
  beforeEach,
  describe,
  expect,
  it,
  vi,
} from 'vitest';
import request from 'supertest';
import { createApp } from '../src/app.js';
import {
  getDatabase,
  disconnectDatabase,
} from '../src/infrastructure/database/prisma.js';
import { SecretBox } from '../src/infrastructure/youtube/secrets.js';
import {
  YoutubeGrants,
  connectionContext,
} from '../src/modules/integrations/youtube/grants.js';
import { YoutubeLinkService } from '../src/modules/integrations/youtube/link-service.js';
import {
  LinkError,
  root,
  readScope,
} from '../src/modules/integrations/youtube/domain.js';
import type {
  ConnectedLibraryProvider,
  ReadContext,
} from '../src/modules/integrations/youtube/library-domain.js';

const uidA = randomUUID(),
  uidB = randomUUID();
const box = new SecretBox('test', new Map([['test', randomBytes(32)]]));
const oauth = {
  authorize: vi.fn(),
  exchange: vi.fn(),
  channel: vi.fn(),
  revoke: vi.fn(),
  refresh: vi.fn(async () => ({ access: randomUUID(), expiresIn: 3600 })),
};
const provider = {
  listChannels: vi.fn<ConnectedLibraryProvider['listChannels']>(),
  listPlaylists: vi.fn<ConnectedLibraryProvider['listPlaylists']>(),
  playlistOwner: vi.fn<ConnectedLibraryProvider['playlistOwner']>(),
  listPlaylistItems: vi.fn<ConnectedLibraryProvider['listPlaylistItems']>(),
  getVideos: vi.fn<ConnectedLibraryProvider['getVideos']>(),
};
const grants = new YoutubeGrants(box, oauth);
const link = new YoutubeLinkService(
  grants,
  new URL('https://api.example.test' + root + '/oauth/callback'),
  new URL('https://app.example.test/return'),
  true,
);
const verifier = {
  async verify(uid: string) {
    return { firebaseUid: uid, provider: 'google.com', googleId: uid };
  },
};
const app = createApp({
  youtubeLinkService: link,
  youtubeLibraryProvider: provider,
  tokenVerifier: verifier,
});
const base = root + '/playlists',
  path = base + '/PLown/items';
const get = (url: string, uid = uidA) =>
  request(app)
    .get(url)
    .set('Authorization', 'Bearer ' + uid);
function playlist(id: string, channelId: string) {
  return {
    id,
    channelId,
    title: 'Lista',
    itemCount: 0,
    thumbnailUrl: null,
    visibility: 'private' as const,
  };
}
const video = 'AAAAAAAAAAA',
  omitted = 'BBBBBBBBBBB';
const entry = (i: number, videoId: string | null = video) => ({
  position: i,
  playlistItemId: 'entry' + i,
  title: 'Elemento ' + i,
  videoId,
});
let ownerA: string, ownerB: string;
async function insertLink(userId: string, channelId: string) {
  const generation = randomUUID();
  const data = {
    subject: userId,
    channelId,
    channelTitle: channelId,
    generation,
    status: 'linked',
    scopes: readScope,
    refreshBox: box.seal(
      randomUUID(),
      connectionContext({ userId, generation }),
    ),
  };
  await getDatabase().externalMusicConnection.upsert({
    where: { userId },
    create: { userId, ...data },
    update: data,
  });
}
describe.skipIf(!process.env.TEST_DATABASE_URL)(
  'lecturas oficiales HTTP y PostgreSQL',
  () => {
    beforeAll(async () => {
      process.env.DATABASE_URL = process.env.TEST_DATABASE_URL;
      ownerA = (
        await getDatabase().user.create({
          data: { firebaseUid: uidA, displayName: 'A' },
        })
      ).id;
      ownerB = (
        await getDatabase().user.create({
          data: { firebaseUid: uidB, displayName: 'B' },
        })
      ).id;
    });
    beforeEach(async () => {
      vi.resetAllMocks();
      oauth.refresh.mockImplementation(async () => ({
        access: randomUUID(),
        expiresIn: 3600,
      }));
      provider.playlistOwner.mockResolvedValue('channelA');
      provider.getVideos.mockImplementation(async (_ctx, ids) =>
        ids
          .filter((x) => x === video)
          .map((id) => ({
            id,
            title: 'Verificado',
            channelTitle: 'Canal que subió el video',
            durationSeconds: 32,
            thumbnailUrl: null,
            availability: 'available',
          })),
      );
      await insertLink(ownerA, 'channelA');
      await insertLink(ownerB, 'channelB');
    });
    afterAll(async () => {
      await getDatabase().externalMusicRevocationJob.deleteMany({
        where: { ownerId: { in: [ownerA, ownerB] } },
      });
      await getDatabase().user.deleteMany({
        where: { id: { in: [ownerA, ownerB] } },
      });
      await disconnectDatabase();
    });
    it('exige Firebase, perfil y vínculo; filtra por canal y conserva listas privadas vacías', async () => {
      await request(app).get(base).expect(401);
      await get(base, randomUUID()).expect(404);
      await get(base).query({ limit: 51 }).expect(400);
      provider.listPlaylists.mockResolvedValue({
        items: [
          playlist('mine', 'channelA'),
          playlist('other', 'channelB'),
          playlist('mine', 'channelA'),
        ],
      });
      const res = await get(base).expect(200);
      expect(res.headers['cache-control']).toBe('no-store');
      expect(res.body.items).toEqual([
        {
          id: 'mine',
          title: 'Lista',
          visibility: 'private',
          itemCount: 0,
          thumbnailUrl: null,
        },
      ]);
      expect(res.body.nextCursor).toBeNull();
      await getDatabase().externalMusicConnection.delete({
        where: { userId: ownerA },
      });
      expect((await get(base).expect(409)).body.error.code).toBe(
        'REAUTHORIZE_YOUTUBE',
      );
    });
    it('comprueba el dueño incluso con un ID de playlist pública conocido', async () => {
      provider.playlistOwner.mockResolvedValue('channelB');
      await get(path).expect(404);
      provider.playlistOwner.mockResolvedValue(null);
      await get(path).expect(404);
      expect(provider.listPlaylistItems).not.toHaveBeenCalled();
      expect(provider.getVideos).not.toHaveBeenCalled();
    });
    it('lee 50 + 18 entradas bajo demanda, conserva repeticiones y omisiones y admite reintento de página', async () => {
      provider.listPlaylistItems.mockImplementation(async (_ctx, _id, req) =>
        req.pageToken
          ? {
              items: [
                entry(49),
                ...Array.from({ length: 18 }, (_, i) => entry(50 + i)),
              ],
            }
          : {
              items: Array.from({ length: 50 }, (_, i) =>
                entry(i, i === 2 ? omitted : i === 3 ? null : video),
              ),
              nextPageToken: 'next-google',
            },
      );
      const one = await get(path).expect(200);
      expect(one.body.items).toHaveLength(50);
      expect(one.body.unavailableCount).toBe(2);
      expect(one.body.items[2]).toMatchObject({
        title: 'Elemento 2',
        availability: 'unavailable',
        openUrl: null,
      });
      expect(one.body.items[3].videoId).toBeNull();
      expect(one.body.items[0]).toMatchObject({
        videoId: video,
        openUrl: 'https://www.youtube.com/watch?v=' + video,
        durationSeconds: 32,
      });
      expect(provider.getVideos.mock.calls[0]![1]).toEqual([video, omitted]);
      expect(provider.listPlaylistItems).toHaveBeenCalledTimes(1);
      const two = await get(path)
        .query({ cursor: one.body.nextCursor })
        .expect(200);
      expect(
        two.body.items.map((x: { position: number }) => x.position),
      ).toEqual(Array.from({ length: 18 }, (_, i) => 50 + i));
      expect(two.body.nextCursor).toBeNull();
      expect(
        (await get(path).query({ cursor: one.body.nextCursor }).expect(200))
          .body.items,
      ).toEqual(two.body.items);
    });
    it('entrega una lista vacía sin consultar videos y asocia metadatos aun si Google los reordena', async () => {
      provider.listPlaylistItems.mockResolvedValueOnce({ items: [] });
      const empty = await get(path).expect(200);
      expect(empty.body).toMatchObject({
        items: [],
        unavailableCount: 0,
        nextCursor: null,
      });
      expect(provider.getVideos).not.toHaveBeenCalled();
      provider.listPlaylistItems.mockResolvedValueOnce({
        items: [entry(0, video), entry(1, omitted)],
      });
      provider.getVideos.mockResolvedValueOnce(
        [omitted, video].map((id) => ({
          id,
          title: 'Title ' + id,
          channelTitle: null,
          durationSeconds: null,
          thumbnailUrl: null,
          availability: 'available' as const,
        })),
      );
      const page = await get(path).expect(200);
      expect(
        page.body.items.map((item: { title: string }) => item.title),
      ).toEqual(['Title ' + video, 'Title ' + omitted]);
    });
    it('mantiene cerradas las lecturas cuando se apaga el piloto', async () => {
      const off = new YoutubeLinkService(
        grants,
        link.callback,
        link.appReturn,
        false,
      );
      const disabled = createApp({
        youtubeLinkService: off,
        youtubeLibraryProvider: provider,
        tokenVerifier: verifier,
      });
      await request(disabled)
        .get(path)
        .set('Authorization', 'Bearer ' + uidA)
        .expect(503);
      expect(provider.playlistOwner).not.toHaveBeenCalled();
    });
    it('liga el cursor a UID, canal, generación, operación, playlist y tamaño', async () => {
      provider.listPlaylistItems.mockResolvedValue({
        items: [],
        nextPageToken: 'p2',
      });
      const cursor = (await get(path).query({ limit: 5 }).expect(200)).body
        .nextCursor;
      expect(provider.getVideos).not.toHaveBeenCalled();
      for (const response of [
        get(path, uidB).query({ cursor }),
        get(base).query({ cursor }),
        get(base + '/other/items').query({ cursor }),
        get(path).query({ cursor, limit: 6 }),
        get(path).query({ cursor: 'x' + cursor }),
      ]) {
        expect((await response.expect(409)).body.error.code).toBe(
          'INVALID_CURSOR',
        );
      }
      await insertLink(ownerA, 'channelA');
      await get(path).query({ cursor }).expect(409);
      expect(provider.listPlaylistItems).toHaveBeenCalledTimes(1);
    });
    it('descarta una respuesta en vuelo después de desvincular', async () => {
      let entered!: () => void;
      const start = new Promise<void>((r) => (entered = r));
      let done!: () => void;
      const gate = new Promise<void>((r) => (done = r));
      provider.listPlaylists.mockImplementationOnce(async () => {
        entered();
        await gate;
        return { items: [playlist('private', 'channelA')] };
      });
      const response = get(base).then((r) => r);
      await start;
      await link.unlink(ownerA);
      done();
      const stale = await response;
      expect(stale.status).toBe(409);
      expect(stale.body.items).toBeUndefined();
    });
    it('renueva una sola vez ante 401, propaga cuota y respeta Retry-After', async () => {
      const rejected = new LinkError(401, 'YOUTUBE_ACCESS_REJECTED');
      provider.listPlaylists
        .mockRejectedValueOnce(rejected)
        .mockResolvedValueOnce({ items: [] });
      await get(base).expect(200);
      expect(oauth.refresh).toHaveBeenCalledTimes(2);
      expect(provider.listPlaylists.mock.calls[0]![0].access).not.toEqual(
        provider.listPlaylists.mock.calls[1]![0].access,
      );
      provider.listPlaylists
        .mockRejectedValueOnce(rejected)
        .mockRejectedValueOnce(rejected);
      expect((await get(base).expect(409)).body.error.code).toBe(
        'REAUTHORIZE_YOUTUBE',
      );
      provider.listPlaylists.mockRejectedValueOnce(
        new LinkError(429, 'YOUTUBE_QUOTA', 31),
      );
      const limited = await get(base).expect(429);
      expect(limited.headers['retry-after']).toBe('31');
    });
    it('un 503 tiene dos reintentos como máximo; una cuota o alcance insuficiente conserva el estado del vínculo', async () => {
      provider.listPlaylists.mockRejectedValue(
        new LinkError(503, 'GOOGLE_UNAVAILABLE'),
      );
      await get(base).expect(503);
      expect(provider.listPlaylists).toHaveBeenCalledTimes(3);
      provider.listPlaylists.mockRejectedValueOnce(
        new LinkError(403, 'MISSING_SCOPE'),
      );
      await get(base).expect(403);
      expect((await link.connection(ownerA)).status).toBe('linked');
    });
    it('corta el reintento si Google pide una espera que supera el presupuesto', async () => {
      provider.listPlaylists.mockImplementationOnce(
        async (ctx: ReadContext) => {
          expect(ctx.signal.aborted).toBe(false);
          throw new LinkError(503, 'GOOGLE_UNAVAILABLE', 30);
        },
      );
      const failed = await get(base).expect(503);
      expect(failed.headers['retry-after']).toBe('30');
      expect(provider.listPlaylists).toHaveBeenCalledTimes(1);
    });
  },
);
