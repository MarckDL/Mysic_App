import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';
import { createApp } from '../src/app.js';
import {
  DiscoveryService,
  type DiscoveryLoader,
} from '../src/modules/catalog/application/discovery-service.js';
import { CatalogLimiter } from '../src/modules/catalog/application/catalog-limiter.js';
import {
  originalDiscovery,
  relatedPage,
} from '../src/infrastructure/music/public-discovery.js';
import {
  shelves,
  group,
} from '../src/infrastructure/music/discovery-mapper.js';

const song = {
  id: 'abcdefghijk',
  title: 'Again',
  artist: 'Artista',
  durationSeconds: 101,
  thumbnail: 'https://i.ytimg.com/vi/abcdefghijk/mqdefault.jpg',
};
const artist = { id: 'UC' + 'a'.repeat(22), name: 'Artista' };
const album = { id: 'MPRE_123', title: 'Disco' };
const view = { view: 'explore' } as const;
const signal = () => new AbortController().signal;
const wire = (serve: (url: URL) => unknown) =>
  vi.fn<typeof fetch>().mockImplementation(async (input, init) => {
    expect(init?.credentials).toBe('omit');
    expect(init?.redirect).toBe('error');
    expect(new Headers(init?.headers).has('Authorization')).toBe(false);
    expect(new Headers(init?.headers).has('Cookie')).toBe(false);
    const url = new URL(String(input));
    expect(url.origin).toBe('https://myslc.duckdns.org');
    return Response.json(serve(url));
  });

describe('descubrimiento musical', () => {
  it('conserva estantes y tipos reales sin incluir podcasts ni Shorts de las búsquedas de videos', () => {
    const rows = shelves([
      {
        header: { title: { text: 'Nuevos álbumes' } },
        contents: [{ item_type: 'album', ...album }],
      },
      {
        header: { title: { text: 'Tendencias' } },
        contents: [
          {
            item_type: 'video',
            id: song.id,
            title: { text: 'Again' },
            artists: [{ name: 'YUI', channel_id: artist.id }],
            duration: { seconds: 123 },
            thumbnail: { contents: [{ url: song.thumbnail }] },
          },
          { item_type: 'podcast_show', ...album },
        ],
      },
    ]);
    expect(rows).toMatchObject([
      { kind: 'album', shelfTitle: 'Nuevos álbumes' },
      {
        kind: 'track',
        mediaType: 'video',
        artist: 'YUI',
        thumbnailUrl: song.thumbnail,
        artistId: artist.id,
        shelfTitle: 'Tendencias',
      },
    ]);
    expect(
      group(
        [
          { ...song, title: 'Clip #Shorts' },
          { ...song, title: 'Short Skirt' },
          { ...song, title: 'duplicate' },
        ],
        'video',
      ),
    ).toMatchObject([{ title: 'Short Skirt', mediaType: 'video' }]);
  });
  it('conserva autor, año y audiencia cuando Music los incluye en las portadas', () => {
    expect(
      group(
        [{ ...album, artists: [{ name: 'YUI' }], year: { text: '2009' } }],
        'album',
      )[0]?.subtitle,
    ).toBe('YUI · 2009');
    expect(
      group(
        [
          {
            ...artist,
            subtitle: { runs: [{ text: 'Artista • 32 mil oyentes' }] },
          },
        ],
        'artist',
      )[0]?.subtitle,
    ).toBe('32 mil oyentes');
    expect(
      group(
        [
          {
            id: 'VLPLrock',
            title: 'Descubrimientos',
            author: { name: 'María' },
          },
        ],
        'playlist',
      )[0]?.subtitle,
    ).toBe('María');
    expect(group([album], 'album')[0]?.subtitle).toBeUndefined();
  });

  it('mezcla búsqueda pública por tipo y conserva el mejor resultado sin filtrar títulos a mano', async () => {
    const transport = wire((url) =>
      url.searchParams.get('type') === 'video'
        ? { type: 'video', items: [{ ...song, id: 'zzzzzzzzzzz' }] }
        : {
            type: 'all',
            top: { kind: 'song', id: song.id, song },
            songs: [song],
            albums: [album],
            artists: [artist],
          },
    );
    const page = await originalDiscovery(transport)(
      { view: 'search', query: 'again', type: 'all' },
      signal(),
    );
    expect(page.items.map((x) => x.shelfTitle)).toEqual([
      'Mejor coincidencia',
      'Canciones',
      'Vídeos',
      'Artistas',
      'Álbumes',
    ]);
    expect(page.items.map((x) => x.kind)).toEqual([
      'track',
      'track',
      'track',
      'artist',
      'album',
    ]);
    expect(transport).toHaveBeenCalledTimes(2);
  });
  it('abre colecciones públicas sin enviar la sesión de escritorio y conserva artistas, miniaturas y orden', async () => {
    const transport = wire((url) =>
      url.pathname.includes('/album/')
        ? {
            ...album,
            thumbnail: song.thumbnail,
            tracks: [{ ...song, thumbnail: [] }, song],
          }
        : {
            name: 'Artista',
            topSongs: [song],
            shelves: [
              { title: 'Albums', items: [{ ...album, kind: 'Single' }] },
            ],
          },
    );
    const load = originalDiscovery(transport);
    const tracks = (await load({ view: 'album', id: album.id }, signal()))
      .items;
    expect(tracks.map((x) => x.id)).toEqual([song.id, song.id]);
    expect(tracks[0]?.thumbnailUrl).toBe(song.thumbnail);
    const page = await load({ view: 'artist', id: artist.id }, signal());
    expect(page).toMatchObject({
      title: 'Artista',
      items: [
        {
          kind: 'track',
          shelfTitle: 'Canciones',
          thumbnailUrl: song.thumbnail,
        },
        { kind: 'album', shelfTitle: 'Álbumes' },
      ],
    });
  });
  it('continúa a la radio real cuando Related solo entrega discos y conserva esas recomendaciones', async () => {
    const music = {
      getRelated: vi.fn().mockResolvedValue({
        contents: [{ title: 'Discos', items: [{ ...album, kind: 'album' }] }],
      }),
      getUpNext: vi.fn().mockResolvedValue({
        contents: [{ ...song, id: 'zzzzzzzzzzz' }, song],
      }),
    };
    const desktop = vi.fn<DiscoveryLoader>();
    const service = new DiscoveryService(async (r, signal) => {
      if (r.view !== 'related') throw new Error();
      return relatedPage(music, r.id, signal);
    }, desktop);
    const result = await service.related(song.id, signal());
    expect(result.items).toMatchObject([
      { kind: 'album', title: 'Disco' },
      { kind: 'track', id: 'zzzzzzzzzzz', shelfTitle: 'Radio de la canción' },
    ]);
    expect(music.getUpNext).toHaveBeenCalledWith(song.id, true);
    expect(desktop).not.toHaveBeenCalled();
    await expect(service.related('bad', signal())).rejects.toThrow();
    await expect(
      service.related(song.id, AbortSignal.abort()),
    ).rejects.toThrow();
  });
  it('conserva las listas recomendadas si la radio pública falla y nunca las pide a una ruta privada', async () => {
    const music = {
      getRelated: async () => ({
        contents: [
          {
            title: 'Listas recomendadas',
            items: [{ kind: 'playlist', id: 'PLabc', title: 'Selección' }],
          },
        ],
      }),
      getUpNext: async () => {
        throw new Error('unavailable');
      },
    };
    const partial = await relatedPage(music, song.id, signal());
    expect(partial.items).toMatchObject([{ kind: 'playlist', id: 'PLabc' }]);
    const transport = wire(() => ({}));
    await expect(
      originalDiscovery(transport)({ view: 'related', id: song.id }, signal()),
    ).rejects.toThrow();
    expect(transport).not.toHaveBeenCalled();
  });
  it('comparte llamadas de catálogo público, recupera fallos y no cachea un error', async () => {
    const load = vi.fn<DiscoveryLoader>().mockRejectedValue(new Error());
    const fallback = vi
      .fn<DiscoveryLoader>()
      .mockRejectedValueOnce(new Error())
      .mockResolvedValue({ items: [], nextCursor: null, excludedCount: 0 });
    const service = new DiscoveryService(load, fallback);
    await expect(service.read(view)).rejects.toThrow();
    await Promise.all([service.read(view), service.read(view)]);
    await service.read(view);
    expect(load).toHaveBeenCalledTimes(2);
    expect(fallback).toHaveBeenCalledTimes(2);
  });
  it('el catálogo por HTTP verifica Firebase, valida tipos e IDs y funciona con la cuenta musical desconectada', async () => {
    const load = vi
      .fn<DiscoveryLoader>()
      .mockResolvedValue({ items: [], nextCursor: null, excludedCount: 0 });
    const app = createApp({
      discoveryService: new DiscoveryService(load, load),
      tokenVerifier: {
        verify: async (token) => ({
          firebaseUid: token,
          provider: 'google.com',
        }),
      },
      catalogLimiter: new CatalogLimiter(undefined, 25),
    });
    const prefix = '/api/v1/catalog/discovery/';
    await request(app)
      .get(prefix + 'explore')
      .expect(401);
    const get = (path: string) =>
      request(app)
        .get(prefix + path)
        .set('Authorization', 'Bearer userA');
    await get('explore?unrelated=wrong').expect(400);
    await get('search?q=a&type=channel').expect(400);
    await get('album/notAlbum').expect(400);
    await get('artist/' + encodeURIComponent('https://x.net')).expect(400);
    await get('search?q=  again  &type=video')
      .expect('Cache-Control', 'private, no-store')
      .expect(200);
    await get('explore').expect(200);
    await get('artist/' + artist.id).expect(200);
    expect(load.mock.calls.map(([r]) => r)).toEqual([
      { view: 'search', query: 'again', type: 'video' },
      view,
      { view: 'artist', id: artist.id },
    ]);
  });
});
