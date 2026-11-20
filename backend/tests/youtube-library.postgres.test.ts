import type { MusicAccountCatalog } from '../src/infrastructure/youtube/music-account-catalog.js';
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

import { youtubeMusicRoot } from '../src/modules/integrations/youtube-music/routes.js';
import type { ChannelMusicProvider } from '../src/modules/integrations/youtube-music/channel-service.js';

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
  subscribedMusicChannels:
    vi.fn<ChannelMusicProvider['subscribedMusicChannels']>(),
  playlistInfo: vi.fn<ChannelMusicProvider['playlistInfo']>(),
  listLikedVideos: vi.fn<ChannelMusicProvider['listLikedVideos']>(),
  searchMusic: vi.fn<ChannelMusicProvider['searchMusic']>(),
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
  channelMusicProvider: provider,
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
      provider.playlistInfo.mockResolvedValue({
        channelId: 'channelA',
        title: 'Mis canciones',
        private: true,
      });
      provider.playlistOwner.mockResolvedValue('channelA');
      provider.getVideos.mockImplementation(async (_ctx, ids) =>
        ids
          .filter((x) => x === video)
          .map((id) => ({
            id,
            title: 'Verificado',
            isRecording: true,
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
    const connection = youtubeMusicRoot + '/connection';
    const musicPath = (generation: string, surface: string) =>
      youtubeMusicRoot + '/connections/' + generation + '/pages/' + surface;
    const recording = {
      id: video,
      title: 'Tema A',
      channelTitle: 'Artista - Topic',
      isRecording: true,
      durationSeconds: 135,
      thumbnailUrl: null,
      availability: 'available' as const,
    };
    it('4026 lee Inicio y Me gusta con el vínculo activo; descarta cursos y sigue una playlist mixta hasta su primera canción', async () => {
      const track = {
        kind: 'track' as const,
        id: video,
        title: 'Tema del canal',
        artist: 'Artista',
        durationSeconds: 45,
        playback: 'native' as const,
      };
      const catalog = {
        verify: vi
          .fn<MusicAccountCatalog['verify']>()
          .mockResolvedValue(undefined),
        read: vi.fn<MusicAccountCatalog['read']>(async (ctx, r, token) => {
          expect(ctx.access).toBeTruthy();
          if (r.surface === 'home')
            return {
              items: [{ ...track, title: 'Recomendación del canal' }],
              excluded: 0,
            };
          if (r.surface === 'liked')
            return {
              items: [{ ...track, title: 'Me gusta musical' }],
              excluded: 0,
            };
          if (r.surface === 'playlists')
            return {
              items: ['PLcurso', 'PLmix'].map((id) => ({
                kind: 'playlist',
                id,
                title: id,
                private: true,
              })),
              excluded: 0,
            };
          if (r.playlistId === 'PLcurso') return { items: [], excluded: 2 };
          if (!token) return { items: [], next: '1', excluded: 1 };
          const n = Number(token);
          return n < 6
            ? { items: [], next: String(n + 1), excluded: 1 }
            : { items: [track], excluded: 0 };
        }),
      };
      const v2 = createApp({
        youtubeLinkService: link,
        channelMusicProvider: provider,
        tokenVerifier: verifier,
        musicAccountCatalog: catalog,
      });
      const view = (p: string, uid = uidA) =>
        request(v2)
          .get('/api/v2/integrations/youtube-music/' + p)
          .set('Authorization', 'Bearer ' + uid);
      const state = (await view('connection').expect(200)).body;
      expect(state.capabilities).toEqual(
        expect.arrayContaining(['home', 'liked', 'albums', 'playback']),
      );
      const page = 'connections/' + state.generation + '/pages/';
      await view(page + 'home', uidB).expect(409);
      expect(catalog.read).not.toHaveBeenCalled();
      expect((await view(page + 'home')).body.items[0].title).toBe(
        'Recomendación del canal',
      );
      expect((await view(page + 'liked')).body.items[0].title).toBe(
        'Me gusta musical',
      );
      const first = (await view(page + 'playlists').expect(200)).body;
      expect(first.items).toEqual([]);
      expect(first.nextCursor).toBeTruthy();
      await view(page + 'liked')
        .query({ cursor: first.nextCursor })
        .expect(409);
      const second = (
        await view(page + 'playlists')
          .query({ cursor: first.nextCursor })
          .expect(200)
      ).body;
      expect(second.items.map((r: { id: string }) => r.id)).toEqual(['PLmix']);
      expect(second.nextCursor).toBeNull();
      expect(provider.listLikedVideos).not.toHaveBeenCalled();
      expect(provider.listPlaylists).not.toHaveBeenCalled();
    });
    it('identifica la música del canal y busca exclusivamente canciones cuando el Inicio personal está denegado', async () => {
      const catalog = {
        verify: vi
          .fn<MusicAccountCatalog['verify']>()
          .mockRejectedValue(new LinkError(403, 'MUSIC_ACCESS_DENIED')),
        read: vi.fn<MusicAccountCatalog['read']>(),
      };
      const search = vi.fn().mockResolvedValue([
        {
          id: 'youtube:' + video,
          source: 'youtube',
          sourceId: video,
          title: 'Again',
          artistName: 'YUI',
          durationSeconds: 247,
          thumbnailUrl: null,
        },
      ]);
      const v2 = createApp({
        musicProvider: { search, getTrack: vi.fn(), resolvePlayback: vi.fn() },
        youtubeLinkService: link,
        channelMusicProvider: provider,
        tokenVerifier: verifier,
        musicAccountCatalog: catalog,
      });
      const view = (path: string, uid = uidA) =>
        request(v2)
          .get('/api/v2/integrations/youtube-music/' + path)
          .set('Authorization', 'Bearer ' + uid);
      const { body: state } = await view('connection').expect(200);
      expect(state).toMatchObject({
        status: 'linked',
        personalization: 'channelOnly',
      });
      expect(state.capabilities).toEqual(
        expect.arrayContaining([
          'playlists',
          'search',
          'channelLiked',
          'playback',
        ]),
      );
      for (const cap of ['home', 'liked', 'songs', 'albums'])
        expect(state.capabilities).not.toContain(cap);
      const path = 'connections/' + state.generation + '/pages/';
      for (const surface of ['home', 'liked', 'albums'])
        await view(path + surface).expect(403);
      expect(provider.listLikedVideos).not.toHaveBeenCalled();
      provider.listLikedVideos.mockResolvedValue({
        items: [
          recording,
          {
            ...recording,
            id: 'ccccccccccc',
            isRecording: false,
            isMusicCategory: false,
          },
        ],
      });
      expect(
        (await view(path + 'channelLiked').expect(200)).body.items,
      ).toMatchObject([{ id: video }]);
      const music = (await view(path + 'search?q=again').expect(200)).body
        .items;
      expect(music).toMatchObject([
        { id: video, artist: 'YUI', playback: 'native' },
      ]);
      expect(search).toHaveBeenCalledWith('again', expect.any(AbortSignal));
      expect(provider.searchMusic).not.toHaveBeenCalled();
      provider.listPlaylists.mockResolvedValue({
        items: [
          {
            id: 'PLmusica',
            channelId: 'channelA',
            title: 'Mi lista musical',
            visibility: 'private',
            itemCount: 1,
            thumbnailUrl: null,
          },
        ],
      });
      provider.listPlaylistItems.mockResolvedValue({
        items: [
          {
            playlistItemId: 'entry',
            position: 0,
            title: 'Pista',
            videoId: video,
          },
        ],
      });
      const playlists = (await view(path + 'playlists').expect(200)).body.items;
      expect(playlists).toMatchObject([{ id: 'PLmusica' }]);
      await view(path + 'search?q=again', uidB).expect(409);
      await view('connection').expect(200);
      expect(catalog.verify).toHaveBeenCalledTimes(1);
      expect(catalog.read).not.toHaveBeenCalled();
    });

    it('mantiene Me gusta de Music cuando la misma cuenta carece de Inicio y álbumes', async () => {
      const denied = new LinkError(403, 'MUSIC_ACCESS_DENIED');
      const musicAccountCatalog: MusicAccountCatalog = {
        verify: vi.fn().mockRejectedValue(denied),
        async verifyCollection(_, surface) {
          if (surface !== 'liked') throw denied;
        },
        read: vi.fn().mockResolvedValue({ items: [], excluded: 0 }),
      };
      const app = createApp({
        youtubeLinkService: link,
        channelMusicProvider: provider,
        tokenVerifier: verifier,
        musicAccountCatalog,
      });
      const read = (path: string) =>
        request(app)
          .get('/api/v2/integrations/youtube-music/' + path)
          .set('Authorization', 'Bearer ' + uidA);
      const { body: state } = await read('connection').expect(200);
      expect(state.personalization).toBe('partialMusic');
      expect(state.capabilities).toContain('liked');
      for (const cap of ['home', 'albums', 'channelLiked'])
        expect(state.capabilities).not.toContain(cap);
      const path = 'connections/' + state.generation + '/pages/';
      await read(path + 'liked').expect(200);
      await read(path + 'home').expect(403);
      expect(provider.listLikedVideos).not.toHaveBeenCalled();
    });
    it('usa el vínculo OAuth de cada UID sin una sesión web y anuncia solo las funciones disponibles', async () => {
      await request(app).get(connection).expect(401);
      const a = (
        await get(connection)
          .expect('Cache-Control', 'private, no-store')
          .expect(200)
      ).body;
      const b = (await get(connection, uidB).expect(200)).body;
      expect(a).toMatchObject({
        provider: 'youtubeOAuth',
        status: 'linked',
        account: { id: 'channelA' },
        accounts: [],
      });
      expect(a.capabilities).toEqual([
        'playlists',
        'playlist',
        'liked',
        'search',
        'artist',
        'artists',
        'songs',
        'mysicRecents',
        'onRepeat',
        'recordInMysic',
      ]);
      expect(b.account.id).toBe('channelB');
      expect(a.generation).not.toBe(b.generation);
      expect(a).not.toHaveProperty('webLinkUrl');
      await get(musicPath(a.generation, 'liked'), uidB).expect(409);
      await get(musicPath(a.generation, 'history')).expect(503);
      await get(musicPath(a.generation, 'home')).expect(503);
      expect(provider.listLikedVideos).not.toHaveBeenCalled();
    });
    it('filtra los Me gusta, protege el cursor y conserva las repeticiones reales de una playlist privada', async () => {
      const { generation } = (await get(connection)).body;
      provider.listLikedVideos.mockResolvedValueOnce({
        items: [
          recording,
          { ...recording, id: omitted, isRecording: false },
          { ...recording, availability: 'unavailable' },
        ],
        nextPageToken: 'more',
      });
      const likes = await get(musicPath(generation, 'liked'))
        .query({ limit: 3 })
        .expect(200);
      expect(likes.body).toMatchObject({
        items: [{ id: video, artist: 'Artista', playback: 'unavailable' }],
        excludedCount: 2,
      });
      expect(likes.body.items[0]).not.toHaveProperty('audioUrl');
      await get(musicPath(generation, 'search'))
        .query({ q: 'tema', cursor: likes.body.nextCursor })
        .expect(409);
      expect(provider.searchMusic).not.toHaveBeenCalled();
      provider.searchMusic.mockResolvedValueOnce({ items: [recording] });
      expect(
        (
          await get(musicPath(generation, 'search'))
            .query({ q: 'tema' })
            .expect(200)
        ).body.items[0].title,
      ).toBe('Tema A');
      provider.listPlaylistItems.mockResolvedValueOnce({
        items: [entry(0), entry(1, omitted), entry(2)],
      });
      const list = await get(musicPath(generation, 'playlist/PLown')).expect(
        200,
      );
      expect(
        list.body.items.map((v: { entryId: string }) => v.entryId),
      ).toEqual(['entry0', 'entry2']);
      expect(list.body.excludedCount).toBe(1);
      expect(list.body.playlist).toMatchObject({
        title: 'Mis canciones',
        private: true,
      });
      provider.playlistInfo.mockResolvedValueOnce({
        channelId: 'channelB',
        title: 'Ajena',
        private: true,
      });
      await get(musicPath(generation, 'playlist/PLforeign')).expect(404);
    });
    it('entrega audio únicamente cuando hay una fuente autorizada para la grabación', async () => {
      const url = 'https://media.example.test/tema.mp3';
      vi.stubEnv('MYSIC_LICENSED_AUDIO_JSON', JSON.stringify({ [video]: url }));
      try {
        const licensed = createApp({
          youtubeLinkService: link,
          channelMusicProvider: provider,
          tokenVerifier: verifier,
        });
        const read = (path: string) =>
          request(licensed)
            .get(path)
            .set('Authorization', 'Bearer ' + uidA);
        const state = await read(connection).expect(200);
        expect(state.body.capabilities).toContain('playback');
        provider.listLikedVideos.mockResolvedValueOnce({
          items: [recording, { ...recording, id: omitted }],
        });
        const tracks = (
          await read(musicPath(state.body.generation, 'liked')).expect(200)
        ).body.items;
        expect(tracks[0]).toMatchObject({
          id: video,
          playback: 'licensed',
          audioUrl: url,
        });
        expect(tracks[1].playback).toBe('unavailable');
        expect(tracks[1]).not.toHaveProperty('audioUrl');
      } finally {
        vi.unstubAllEnvs();
      }
    });
    it('reanuda una playlist mixta con la primera canción en la cuarta página', async () => {
      const { generation } = (await get(connection)).body;
      provider.listPlaylists.mockResolvedValue({
        items: [{ ...playlist('PLmix', 'channelA'), itemCount: 151 }],
      });
      provider.listPlaylistItems.mockImplementation(async (_ctx, _id, page) => {
        const start = Number(page.pageToken ?? '0');
        return {
          items:
            start < 150
              ? Array.from({ length: 50 }, (_, i) => entry(start + i, omitted))
              : [entry(150)],
          nextPageToken: start < 150 ? String(start + 50) : undefined,
        };
      });
      const first = await get(musicPath(generation, 'playlists')).expect(200);
      expect(first.body.items).toEqual([]);
      expect(first.body.nextCursor).toBeTruthy();
      expect(provider.listPlaylistItems).toHaveBeenCalledTimes(3);
      expect(provider.listPlaylists).toHaveBeenCalledTimes(1);
      const next = await get(musicPath(generation, 'playlists'))
        .query({ cursor: first.body.nextCursor })
        .expect(200);
      expect(next.body).toMatchObject({
        items: [{ kind: 'playlist', id: 'PLmix', private: true }],
        nextCursor: null,
      });
      expect(provider.listPlaylistItems).toHaveBeenCalledTimes(4);
    });
    it('descarta Me gusta en vuelo y un intento de desvinculación tardío al cambiar de canal', async () => {
      const { generation } = (await get(connection)).body;
      let enter!: () => void, proceed!: () => void;
      const entered = new Promise<void>((resolve) => (enter = resolve));
      const gate = new Promise<void>((resolve) => (proceed = resolve));
      provider.listLikedVideos.mockImplementationOnce(async () => {
        enter();
        await gate;
        return { items: [recording] };
      });
      const reading = get(musicPath(generation, 'liked')).then(
        (response) => response,
      );
      await entered;
      await insertLink(ownerA, 'replacement');
      proceed();
      const stale = await reading;
      expect(stale.status).toBe(409);
      expect(stale.body).not.toHaveProperty('items');
      await request(app)
        .delete(youtubeMusicRoot + '/connections/' + generation)
        .set('Authorization', 'Bearer ' + uidA)
        .expect(409);
      await request(app)
        .delete(root + '/connection')
        .query({ generation })
        .set('Authorization', 'Bearer ' + uidA)
        .expect(409);
      expect((await get(connection)).body.account.id).toBe('replacement');
    });
    it('reúne las canciones de varias listas propias, deduplica y conserva las posiciones en el detalle', async () => {
      const { generation } = (await get(connection)).body;
      provider.listPlaylists.mockImplementation(async (_ctx, page) =>
        page.pageToken
          ? { items: [{ ...playlist('PLb', 'channelA'), itemCount: 2 }] }
          : {
              items: [{ ...playlist('PLa', 'channelA'), itemCount: 1 }],
              nextPageToken: 'b',
            },
      );
      provider.getVideos.mockImplementation(async (_ctx, ids) =>
        ids.map((id) => ({ ...recording, id })),
      );
      provider.listPlaylistItems.mockImplementation(async (_ctx, id, page) =>
        id === 'PLa'
          ? { items: [entry(0, video)] }
          : page.pageToken
            ? { items: [entry(1, omitted)] }
            : { items: [entry(0, video)], nextPageToken: 'next-song' },
      );
      const first = await get(musicPath(generation, 'songs'))
        .query({ limit: 1 })
        .expect(200);
      expect(first.body.items.map((r: { id: string }) => r.id)).toEqual([
        video,
      ]);
      const next = await get(musicPath(generation, 'songs'))
        .query({ cursor: first.body.nextCursor })
        .expect(200);
      expect(next.body.items).toEqual([]);
      const last = await get(musicPath(generation, 'songs'))
        .query({ cursor: next.body.nextCursor })
        .expect(200);
      expect(last.body.items.map((r: { id: string }) => r.id)).toEqual([
        omitted,
      ]);
    });
    it('separa los canales musicales seguidos de la búsqueda de grabaciones de un canal', async () => {
      const { generation } = (await get(connection)).body;
      const artistId = 'UC' + 'a'.repeat(22);
      provider.subscribedMusicChannels.mockResolvedValue({
        items: [{ kind: 'artist', id: artistId, title: 'Grupo' }],
        nextPageToken: 'more',
      });
      const list = await get(musicPath(generation, 'artists')).expect(200);
      expect(list.body.items).toEqual([
        { kind: 'artist', id: artistId, title: 'Grupo' },
      ]);
      provider.searchMusic.mockResolvedValue({
        items: [
          { ...recording, artistId },
          { ...recording, id: omitted, artistId: 'UC' + 'b'.repeat(22) },
        ],
      });
      const detail = await get(
        musicPath(generation, 'artist/' + artistId),
      ).expect(200);
      expect(detail.body.items[0].artistId).toBe(artistId);
      expect(detail.body.items).toHaveLength(1);
      expect(provider.searchMusic.mock.calls[0]![3]).toBe(artistId);
      await get(musicPath(generation, 'artist/invalid')).expect(400);
      await get(musicPath(generation, 'artist/' + artistId))
        .query({ cursor: list.body.nextCursor })
        .expect(409);
      await get(musicPath(generation, 'artists'), uidB).expect(409);
    });
    it('registra una escucha de Mysic una sola vez entre dispositivos y exige vínculo y tiempo efectivo', async () => {
      const { generation, activityEpoch } = (await get(connection)).body;
      const id = randomUUID(),
        path =
          youtubeMusicRoot + '/connections/' + generation + '/listens/' + id;
      const body = { trackId: video, listenedMs: 32000, activityEpoch };
      const put = (data: unknown, owner = uidA) =>
        request(app)
          .put(path)
          .set('Authorization', 'Bearer ' + owner)
          .send(data as object);
      await put({ ...body, listenedMs: 300 }).expect(400);
      await put(body, uidB).expect(409);
      await Promise.all([put(body).expect(204), put(body).expect(204)]);
      const rows = await getDatabase().channelMusicListen.count({
        where: { userId: ownerA, generation },
      });
      expect(rows).toBe(1);
      const [table] = await getDatabase().$queryRaw<
        { relrowsecurity: boolean }[]
      >`SELECT relrowsecurity FROM pg_class WHERE oid = 'mysic.channel_music_listens'::regclass`;
      expect(table?.relrowsecurity).toBe(true);
      await put({ ...body, trackId: omitted }).expect(409);
      expect((await get(path).expect(200)).body.listen).toEqual({
        trackId: video,
        listenedMs: 32000,
      });
      expect(
        (await get(musicPath(generation, 'mysicRecents')).expect(200)).body
          .items[0].id,
      ).toBe(video);
      expect(
        (await get(musicPath(generation, 'onRepeat')).expect(200)).body.items,
      ).toEqual([]);
      await get(musicPath(generation, 'history')).expect(503);
    });
    it('descarta la página en vuelo y el cursor anterior si otro dispositivo borra la actividad', async () => {
      const { generation } = (await get(connection)).body;
      await getDatabase().channelMusicListen.createMany({
        data: [1500, 90000].map((age) => ({
          userId: ownerA,
          generation,
          videoId: video,
          listenId: randomUUID(),
          listenedMs: 32000,
          playedAt: new Date(Date.now() - age),
        })),
      });
      const path = musicPath(generation, 'mysicRecents');
      const first = await get(path).query({ limit: 1 }).expect(200);
      expect(first.body.nextCursor).toBeTruthy();
      let enter!: () => void, resume!: () => void;
      const entered = new Promise<void>((resolve) => (enter = resolve));
      const gate = new Promise<void>((resolve) => (resume = resolve));
      provider.getVideos.mockImplementationOnce(async () => {
        enter();
        await gate;
        return [recording];
      });
      const inFlight = get(path).then((response) => response);
      await entered;
      try {
        await request(app)
          .delete(youtubeMusicRoot + '/connections/' + generation + '/activity')
          .set('Authorization', 'Bearer ' + uidA)
          .expect(204);
      } finally {
        resume();
      }
      const stale = await inFlight;
      expect(stale.status).toBe(409);
      expect(stale.body.error.code).toBe('MYSIC_ACTIVITY_CHANGED');
      expect(stale.body).not.toHaveProperty('items');
      await get(path).query({ cursor: first.body.nextCursor }).expect(409);
      expect((await get(path).expect(200)).body.items).toEqual([]);
    });
    it('calcula En repetición en 30 días, ignora repeticiones inmediatas y respeta pausas y borrado', async () => {
      const { generation, activityEpoch } = (await get(connection)).body;
      const now = Date.now();
      const activity =
        youtubeMusicRoot + '/connections/' + generation + '/activity';
      const write = (id: string, epoch: number) =>
        request(app)
          .put(
            youtubeMusicRoot + '/connections/' + generation + '/listens/' + id,
          )
          .set('Authorization', 'Bearer ' + uidA)
          .send({ trackId: video, listenedMs: 32000, activityEpoch: epoch });
      const pause = (paused: boolean, uid = uidA) =>
        request(app)
          .put(activity)
          .set('Authorization', 'Bearer ' + uid)
          .send({ paused });
      await getDatabase().channelMusicListen.createMany({
        data: [5000, 10000, 90000, 32 * 86400000].map((age) => ({
          userId: ownerA,
          generation,
          listenId: randomUUID(),
          videoId: video,
          listenedMs: 32000,
          playedAt: new Date(now - age),
        })),
      });
      const ranking = await get(musicPath(generation, 'onRepeat')).expect(200);
      expect(ranking.body.items).toHaveLength(1);
      expect(ranking.body.items[0]).toMatchObject({ id: video, playCount: 2 });
      await pause(true, uidB).expect(409);
      await pause(true).expect(204);
      const paused = (await get(connection)).body;
      expect(paused.account.historyPaused).toBe(true);
      await pause(true).expect(204);
      expect((await get(connection)).body.activityEpoch).toBe(
        paused.activityEpoch,
      );
      await write(randomUUID(), paused.activityEpoch).expect(409);
      await pause(false).expect(204);
      await request(app)
        .delete(activity)
        .set('Authorization', 'Bearer ' + uidA)
        .expect(204);
      const current = (await get(connection)).body;
      await write(randomUUID(), activityEpoch).expect(409);
      expect(
        (await get(musicPath(generation, 'mysicRecents')).expect(200)).body
          .items,
      ).toEqual([]);
      await write(randomUUID(), current.activityEpoch).expect(204);
      await link.unlink(ownerA, generation);
      expect(
        await getDatabase().channelMusicListen.count({
          where: { userId: ownerA },
        }),
      ).toBe(0);
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
      const music = await request(disabled)
        .get(connection)
        .set('Authorization', 'Bearer ' + uidA)
        .expect(200);
      expect(music.body).toMatchObject({
        status: 'unavailable',
        account: { id: 'channelA' },
        capabilities: [],
      });
      await request(disabled)
        .get(musicPath(music.body.generation, 'liked'))
        .set('Authorization', 'Bearer ' + uidA)
        .expect(503);
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
