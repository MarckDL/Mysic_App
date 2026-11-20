import { randomBytes } from 'node:crypto';
import { describe, expect, it, vi } from 'vitest';
import { YoutubeDataLibraryProvider } from '../src/infrastructure/youtube/youtube-data-library-provider.js';
import { SecretBox } from '../src/infrastructure/youtube/secrets.js';
import { LibraryCursors } from '../src/modules/integrations/youtube/library-cursor.js';

import { licensedRecordings } from '../src/modules/integrations/youtube-music/channel-service.js';

const ctx = { access: 'test-grant', signal: new AbortController().signal };
const id = 'ABCDEFGHIJK';
describe('biblioteca oficial de YouTube', () => {
  it('pide solo canales propios y listas propias con campos parciales y OAuth en cabecera', async () => {
    const fetcher = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(
        Response.json({
          items: [{ id: 'channel', snippet: { title: 'Canal' } }],
        }),
      )
      .mockResolvedValueOnce(
        Response.json({
          nextPageToken: 'p2',
          items: [
            {
              id: 'PLtest',
              snippet: {
                channelId: 'channel',
                title: 'Privada',
                thumbnails: {
                  medium: { url: 'https://i.ytimg.com/example.jpg' },
                },
              },
              status: { privacyStatus: 'private' },
              contentDetails: { itemCount: 0 },
            },
          ],
        }),
      );
    const api = new YoutubeDataLibraryProvider(fetcher);
    expect((await api.listChannels(ctx)).items[0]?.title).toBe('Canal');
    expect(
      await api.listPlaylists(ctx, { maxResults: 15, pageToken: 'p1' }),
    ).toMatchObject({
      nextPageToken: 'p2',
      items: [
        {
          id: 'PLtest',
          visibility: 'private',
          itemCount: 0,
          thumbnailUrl: 'https://i.ytimg.com/example.jpg',
        },
      ],
    });
    for (const [input, init] of fetcher.mock.calls) {
      const url = new URL(String(input));
      expect(url.origin).toBe('https://www.googleapis.com');
      expect(url.searchParams.get('mine')).toBe('true');
      expect(url.href).not.toContain(ctx.access);
      expect(init?.headers).toEqual({ Authorization: 'Bearer ' + ctx.access });
      expect(init?.redirect).toBe('error');
    }
    expect(
      new URL(String(fetcher.mock.calls[1]![0])).searchParams.get('pageToken'),
    ).toBe('p1');
  });
  it('lee propietario y conserva entradas incompletas sin inferir videos ni destinos', async () => {
    const fetcher = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(
        Response.json({
          items: [{ id: 'wrong', snippet: { channelId: 'foreign' } }],
        }),
      )
      .mockResolvedValueOnce(
        Response.json({
          items: [
            {
              id: 'entry',
              snippet: { position: 4, title: 'Elemento' },
              contentDetails: { videoId: 'not/an/id' },
            },
          ],
        }),
      );
    const api = new YoutubeDataLibraryProvider(fetcher);
    expect(await api.playlistOwner(ctx, 'PLtest')).toBeNull();
    expect(
      await api.listPlaylistItems(ctx, 'PLtest', { maxResults: 50 }),
    ).toMatchObject({
      items: [{ playlistItemId: 'entry', position: 4, videoId: null }],
    });
    const url = new URL(String(fetcher.mock.calls[0]![0]));
    expect(url.searchParams.get('id')).toBe('PLtest');
    expect(url.searchParams.has('mine')).toBe(false);
  });
  it('interpreta duración, datos incompletos, imágenes y restricciones de un lote', async () => {
    const videos = [
      {
        id,
        snippet: {
          title: 'Título',
          channelTitle: 'Canal',
          thumbnails: { high: { url: 'https://wrong.example/image.png' } },
        },
        contentDetails: { duration: 'P1DT2H3M4S' },
        status: { privacyStatus: 'private', uploadStatus: 'processed' },
      },
      { id: 'BBBBBBBBBBB', status: { uploadStatus: 'failed' } },
      {
        id: 'CCCCCCCCCCC',
        status: { uploadStatus: 'processed', privacyStatus: 'public' },
        contentDetails: { regionRestriction: { allowed: ['PE'] } },
      },
      { id: 'DDDDDDDDDDD' },
      {
        id: 'EEEEEEEEEEE',
        contentDetails: { regionRestriction: { allowed: [] } },
      },
    ];
    const transport = vi.fn(async () => Response.json({ items: videos }));
    const api = new YoutubeDataLibraryProvider(transport);
    expect(await api.getVideos(ctx, [])).toEqual([]);
    await expect(api.getVideos(ctx, Array(51).fill(id))).rejects.toThrow();
    const result = await api.getVideos(
      ctx,
      videos.map((x) => x.id),
    );
    expect(transport).toHaveBeenCalledTimes(1);
    expect(result[0]).toMatchObject({
      durationSeconds: 93784,
      thumbnailUrl: null,
      availability: 'available',
      channelTitle: 'Canal',
    });
    expect(result.map((x) => x.availability)).toEqual([
      'available',
      'unavailable',
      'unknown',
      'unknown',
      'unavailable',
    ]);
  });
  it('usa la categoría musical y las líneas de atribución de las grabaciones para búsqueda y Me gusta', async () => {
    const attributions =
      'Provided to YouTube by Label\nArtist · Song\nAuto-generated by YouTube.';
    const clip = (id: string, categoryId: string, description: string) => ({
      id,
      snippet: { categoryId, description, title: 'Título' },
    });
    const videos = [
      clip(id, '10', attributions),
      clip('BBBBBBBBBBB', '10', 'Concierto casero'),
      clip('CCCCCCCCCCC', '22', attributions),
    ];
    const fetcher = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(
        Response.json({ items: videos, nextPageToken: 'next' }),
      )
      .mockResolvedValueOnce(
        Response.json({
          items: [{ id: { videoId: id } }, { id: { videoId: 'BBBBBBBBBBB' } }],
          nextPageToken: 'search-next',
        }),
      )
      .mockResolvedValueOnce(
        Response.json({ items: videos.slice(0, 2).reverse() }),
      );
    const api = new YoutubeDataLibraryProvider(fetcher);
    const liked = await api.listLikedVideos(ctx, {
      maxResults: 3,
      pageToken: 'likes-next',
    });
    expect(liked.items.map((v) => v.isRecording)).toEqual([true, false, false]);
    expect(liked.nextPageToken).toBe('next');
    const found = await api.searchMusic(ctx, 'título', { maxResults: 5 });
    expect(found.nextPageToken).toBe('search-next');
    expect(found.items.map((v) => v.id)).toEqual([id, 'BBBBBBBBBBB']);
    const urls = fetcher.mock.calls.map(([input]) => new URL(String(input)));
    expect(urls[0]!.searchParams.get('myRating')).toBe('like');
    expect(urls[0]!.searchParams.get('pageToken')).toBe('likes-next');
    expect(urls[1]!.searchParams.get('videoCategoryId')).toBe('10');
    expect(urls[1]!.searchParams.get('q')).toBe('título');
    expect(urls[2]!.searchParams.get('id')).toBe(id + ',BBBBBBBBBBB');
  });
  it('clasifica las suscripciones a partir de datos de canales de Google y respeta el orden del usuario', async () => {
    const a = 'UC' + 'A'.repeat(22),
      b = 'UC' + 'B'.repeat(22),
      c = 'UC' + 'C'.repeat(22);
    const fetcher = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(
        Response.json({
          items: [a, b, c].map((channelId) => ({
            snippet: { resourceId: { channelId } },
          })),
          nextPageToken: 'next',
        }),
      )
      .mockResolvedValueOnce(
        Response.json({
          items: [
            {
              id: c,
              snippet: { title: 'C' },
              topicDetails: { topicIds: ['/m/03_d0'] },
            },
            {
              id: b,
              snippet: { title: 'Noticias' },
              topicDetails: {
                topicCategories: ['https://en.wikipedia.org/wiki/Politics'],
              },
            },
            {
              id: a,
              snippet: { title: 'A' },
              topicDetails: {
                topicCategories: ['https://en.wikipedia.org/wiki/Music'],
              },
            },
          ],
        }),
      );
    const api = new YoutubeDataLibraryProvider(fetcher);
    const page = await api.subscribedMusicChannels(ctx, { maxResults: 3 });
    expect(page.items.map((x) => x.id)).toEqual([a, c]);
    expect(page.nextPageToken).toBe('next');
    expect(
      new URL(String(fetcher.mock.calls[0]![0])).searchParams.get('mine'),
    ).toBe('true');
    expect(
      new URL(String(fetcher.mock.calls[1]![0])).searchParams.get('id'),
    ).toBe([a, b, c].join(','));
  });
  it('acepta fuentes HTTPS explícitas y rechaza identificadores o direcciones con credenciales', () => {
    expect(licensedRecordings(undefined).size).toBe(0);
    const media = 'https://media.example.test/tema.mp3';
    expect(licensedRecordings(JSON.stringify({ [id]: media })).get(id)).toBe(
      media,
    );
    for (const url of [
      'http://example.test/a',
      'https://user:pass@example.test/a',
      media + '?token=x',
      media + '#x',
    ])
      expect(() => licensedRecordings(JSON.stringify({ [id]: url }))).toThrow();
    expect(() =>
      licensedRecordings(JSON.stringify({ invalid: media })),
    ).toThrow();
  });
  it.each([
    [401, 'authError', 401, 'YOUTUBE_ACCESS_REJECTED'],
    [403, 'insufficientPermissions', 403, 'MISSING_SCOPE'],
    [403, 'playlistItemsNotAccessible', 403, 'YOUTUBE_FORBIDDEN'],
    [403, 'quotaExceeded', 429, 'YOUTUBE_QUOTA'],
    [429, 'rateLimitExceeded', 429, 'YOUTUBE_QUOTA'],
    [404, 'playlistNotFound', 404, 'PLAYLIST_NOT_FOUND'],
    [400, 'invalidPageToken', 409, 'INVALID_CURSOR'],
    [503, 'backendError', 503, 'GOOGLE_UNAVAILABLE'],
  ] as const)('distingue HTTP %s / %s', async (http, reason, status, code) => {
    const api = new YoutubeDataLibraryProvider(async () =>
      Response.json(
        { error: { errors: [{ reason }] } },
        { status: http, headers: { 'Retry-After': '37' } },
      ),
    );
    await expect(
      api.listPlaylists(ctx, { maxResults: 5 }),
    ).rejects.toMatchObject({
      status,
      code,
      ...(status === 429 || status === 503 ? { retryAfter: 37 } : {}),
    });
  });
  it('rechaza un documento inválido y limita el tamaño de una página del proveedor', async () => {
    const api = new YoutubeDataLibraryProvider(async () =>
      Response.json({
        items: Array(51).fill({ id: 'entry', snippet: { position: 1 } }),
      }),
    );
    await expect(
      api.listPlaylistItems(ctx, 'PLtest', { maxResults: 50 }),
    ).rejects.toMatchObject({ code: 'GOOGLE_INVALID_RESPONSE' });
  });
  it('invalida el cursor al vencer, al reiniciarse o al cambiar su contexto', () => {
    let now = 1;
    const box = new SecretBox('qa', new Map([['qa', randomBytes(32)]]));
    const cursors = new LibraryCursors(box, () => now);
    const start = cursors.resume('owner:a');
    const next = cursors.next('owner:a', start, ['rowId'], 'google-token')!;
    expect(next).not.toContain('google-token');
    expect(cursors.resume('owner:a', next).seen.has('rowId')).toBe(true);
    expect(() => cursors.resume('owner:b', next)).toThrow('INVALID_CURSOR');
    expect(() => cursors.resume('owner:a', next, 1)).toThrow('INVALID_CURSOR');
    expect(() =>
      new LibraryCursors(box, () => now).resume('owner:a', next),
    ).toThrow('CURSOR_EXPIRED');
    const following = cursors.resume('owner:a', next);
    expect(() =>
      cursors.next('owner:a', following, [], 'google-token'),
    ).toThrow('GOOGLE_INVALID_RESPONSE');
    now += 900001;
    expect(() => cursors.resume('owner:a', next)).toThrow();
  });
});
